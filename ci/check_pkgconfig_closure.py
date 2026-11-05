#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
check_pkgconfig_closure.py — pkg-config 依赖闭包体检

为什么需要它
------------
`configure: error: gstreamer-1.0 base plugins development files not found`
这条报错**永远不说缺什么**。真实链路是：

  1. wine 的 WINE_PACKAGE_FLAGS 调 pkg-config --cflags/--libs <模块们>
  2. 任一传递依赖的 .pc 缺失 → pkg-config 整体返回空 + rc=1
  3. 空的 cflags/libs 让后面的 AC_CHECK_LIB 段被跳过
  4. 最终只剩一句 "development files not found"

结果就是：一次只能暴露一个缺口，补完再跑一轮，再暴露下一个。
实际排过 8 轮（xcb → xau → xdmcp → ... → libgstreamer-gl1.0-0）。

另一个更隐蔽的坑是**悬空软链接**：
  libgstgl-1.0.so -> libgstgl-1.0.so.0      (来自 *-dev 包)
  但 libgstgl-1.0.so.0 由别的包提供且未下载
此时 `ls libgstgl-1.0.so` 通过，ld 却报 `cannot find -lgstgl-1.0`。
所以本脚本对 .so 一律用 `os.path.isfile()`（跟随软链）判定，
而不是 os.path.exists()/lexists()。

用法
----
    python3 ci/check_pkgconfig_closure.py \
        --pc-dir /usr/aarch64-linux-gnu/lib/pkgconfig \
        --lib-dir /usr/aarch64-linux-gnu/lib \
        --require gstreamer-1.0,gstreamer-video-1.0,...,gstreamer-gl-1.0

    # 也可直接从 configure.ac 自动提取 wine 的 GSTREAMER 模块
    python3 ci/check_pkgconfig_closure.py --from-configure-ac configure.ac

退出码：0 全部可达；1 有缺失/悬空。
"""

import argparse
import os
import re
import sys


# ---------------------------------------------------------------- .pc 解析
def parse_pc(path):
    """返回 (name, requires_list, requires_private_list, libs, cflags)。"""
    name = None
    reqs, reqs_priv, libs, cflags = [], [], "", ""
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            for raw in f:
                line = raw.rstrip("\n")
                if not line or line.lstrip().startswith("#"):
                    continue
                if ":" not in line:
                    continue
                key, _, val = line.partition(":")
                key = key.strip()
                val = val.strip()
                if key == "Name" and name is None:
                    name = val
                elif key == "Requires":
                    reqs = _split_requires(val)
                elif key == "Requires.private":
                    reqs_priv = _split_requires(val)
                elif key == "Libs":
                    libs = val
                elif key == "Cflags":
                    cflags = val
    except OSError:
        return None
    return (name, reqs, reqs_priv, libs, cflags)


def _split_requires(val):
    out = []
    for tok in val.split(","):
        tok = tok.strip()
        if not tok:
            continue
        # 去掉版本约束：foo >= 1.2 / foo = 1.0 / foo < 2
        mod = re.split(r"[\s<>=!]", tok, maxsplit=1)[0].strip()
        if mod:
            out.append(mod)
    return out


def build_index(pc_dirs):
    """建立 模块名 -> .pc 路径 的索引。"""
    idx = {}
    for d in pc_dirs:
        if not os.path.isdir(d):
            continue
        for entry in os.listdir(d):
            if not entry.endswith(".pc"):
                continue
            mod = entry[:-3]
            full = os.path.join(d, entry)
            if os.path.isfile(full) and mod not in idx:
                idx[mod] = full
    return idx


# ------------------------------------------------------- 递归闭包 + 三分法
def walk_closure(roots, idx):
    """
    返回 dict:
      reachable : set 成功解析到的模块
      missing   : set 完全找不到 .pc 的模块
      edges     : dict child -> set(parents)，用于报告是谁引入的

    注意：缺失节点本身无法展开（没有 .pc 可读），所以它的子依赖在
    真实环境里同样未知。为了给使用者一个"可能还缺这些"的提示，
    调用方可以额外传入 hint_idx（例如 CI 上另一台机器的完整索引）。
    """
    reachable, missing = set(), set()
    edges = {}
    stack = list(roots)
    while stack:
        mod = stack.pop()
        if mod in reachable or mod in missing:
            continue
        path = idx.get(mod)
        if not path:
            missing.add(mod)
            continue
        parsed = parse_pc(path)
        if parsed is None:
            missing.add(mod)
            continue
        reachable.add(mod)
        _, reqs, reqs_priv, _, _ = parsed
        # Requires.private 也必须可达：静态链接与 -rpath-link 会用到
        for child in set(reqs) | set(reqs_priv):
            edges.setdefault(child, set()).add(mod)
            stack.append(child)
    return {"reachable": reachable, "missing": missing, "edges": edges}


# --------------------------------------------------------------- 包名建议
# 缺失的 .pc -> 提供它的 Debian/Ubuntu 包名。
# 这张表是「排错经验」的沉淀：都是实际踩过的坑，尤其是 X 依赖链
# （x11 -> xcb -> xau/xdmcp）和 gstreamer 的 gl 拆包问题。
#
# 覆盖不到时，脚本会退化为只报 .pc 名，并提示用 apt-file 自行查询。
PC_TO_PACKAGE = {
    # --- X 协议 / 核心库链：x11 -> xcb -> {xau, xdmcp} ---
    "x11":              "libx11-dev",
    "x11-xcb":          "libx11-xcb-dev",
    "xcb":              "libxcb1-dev",
    "xau":              "libxau-dev",
    "xdmcp":            "libxdmcp-dev",
    "xproto":           "x11proto-dev",
    "xext":             "libxext-dev",
    "xrender":          "libxrender-dev",
    "xi":               "libxi-dev",
    "xtst":             "libxtst-dev",
    "xfixes":           "libxfixes-dev",
    "xcursor":          "libxcursor-dev",
    "xrandr":           "libxrandr-dev",
    "xinerama":         "libxinerama-dev",
    "xcomposite":       "libxcomposite-dev",
    "xdamage":          "libxdamage-dev",
    "xxf86vm":          "libxxf86vm-dev",
    "xkbcommon":        "libxkbcommon-dev",
    # --- GL / EGL / DRM ---
    "gl":               "libgl-dev",
    "egl":              "libegl-dev",
    "glesv2":           "libgles-dev",
    "glx":              "libglx-dev",
    "gbm":              "libgbm-dev",
    "libdrm":           "libdrm-dev",
    # --- gstreamer ---
    "gstreamer-1.0":    "libgstreamer1.0-dev",
    "gstreamer-gl-1.0": "libgstreamer-plugins-base1.0-dev",
    "gstreamer-video-1.0": "libgstreamer-plugins-base1.0-dev",
    "gstreamer-audio-1.0": "libgstreamer-plugins-base1.0-dev",
    "gstreamer-tag-1.0":   "libgstreamer-plugins-base1.0-dev",
    "gstreamer-base-1.0":  "libgstreamer-plugins-base1.0-dev",
    "gstreamer-allocators-1.0": "libgstreamer-plugins-base1.0-dev",
    # --- glib 家族 ---
    "glib-2.0":         "libglib2.0-dev",
    "gobject-2.0":      "libglib2.0-dev",
    "gmodule-no-export-2.0": "libglib2.0-dev",
    "gthread-2.0":      "libglib2.0-dev",
    "gio-2.0":          "libglib2.0-dev",
    "libffi":           "libffi-dev",
    "pcre2":            "libpcre2-dev",
    "zlib":             "zlib1g-dev",
    "orc-0.4":          "liborc-0.4-dev",
    # --- udev / wayland / 其它 ---
    "gudev-1.0":        "libgudev-1.0-dev",
    "libudev":          "libudev-dev",
    "wayland-client":   "libwayland-dev",
    "wayland-cursor":   "libwayland-dev",
    "wayland-egl":      "libwayland-dev",
    "wayland-server":   "libwayland-dev",
    "wayland-protocols": "wayland-protocols",
    "alsa":             "libasound2-dev",
    "libpulse":         "libpulse-dev",
    "vulkan":           "libvulkan-dev",
    "freetype2":        "libfreetype-dev",
    "fontconfig":       "libfontconfig-dev",
}

# .so 实体 -> 提供它的 runtime 包（-dev 包只放软链，实体常在别的包里）
# 这一条是昨天 libgstgl-1.0.so 悬空的直接教训。
SONAME_TO_PACKAGE = {
    "libgstgl-1.0.so":  "libgstreamer-gl1.0-0",
    "libgstvideo-1.0.so": "libgstreamer-plugins-base1.0-0",
    "libgstaudio-1.0.so": "libgstreamer-plugins-base1.0-0",
    "libgsttag-1.0.so":   "libgstreamer-plugins-base1.0-0",
    "libgstbase-1.0.so":  "libgstreamer-plugins-base1.0-0",
    "libgstreamer-1.0.so": "libgstreamer1.0-0",
    "libudev.so":         "libudev1",
    "libgbm.so":          "libgbm1",
}


def suggest(missing, dangling):
    """把缺失项翻译成可执行的包名建议。"""
    pkgs = {}
    unknown = []
    for mod in missing:
        pkg = PC_TO_PACKAGE.get(mod)
        if pkg:
            pkgs.setdefault(pkg, []).append("%s.pc" % mod)
        else:
            unknown.append("%s.pc" % mod)
    for _mod, lib, _tgt, _why in dangling:
        pkg = SONAME_TO_PACKAGE.get(lib)
        if pkg:
            pkgs.setdefault(pkg, []).append(lib)
        else:
            unknown.append(lib)
    return pkgs, unknown


def check_sonames(pc_paths, lib_dirs):
    """
    对给定 .pc 的 Libs 里所有 -lXXX 检查实体是否存在。
    关键：用 isfile（跟随软链）而不是 exists/lexists，
    否则悬空软链会被漏掉。
    """
    dangling = []          # (mod, libname, 软链目标, 原因)
    seen = set()
    for mod, pc_path in pc_paths:
        parsed = parse_pc(pc_path)
        if not parsed:
            continue
        _, _, _, libs, _ = parsed
        for tok in libs.split():
            if not tok.startswith("-l"):
                continue
            lib = tok[2:]
            if (mod, lib) in seen:
                continue
            seen.add((mod, lib))
            found = None
            for d in lib_dirs:
                so = os.path.join(d, "lib%s.so" % lib)
                if os.path.isfile(so):
                    found = so
                    break
                if os.path.lexists(so) and found is None:
                    # 软链存在但目标不可打开 => 悬空
                    found = so
            if found is None:
                dangling.append((mod, "lib%s.so" % lib, "", "找不到 .so"))
                continue
            if not os.path.isfile(found):
                tgt = ""
                try:
                    tgt = os.readlink(found)
                except OSError:
                    pass
                dangling.append((mod, os.path.basename(found), tgt,
                                 "软链目标不存在"))
    return dangling


# ------------------------------------------------------------- configure.ac
def modules_from_configure_ac(path):
    """从 configure.ac 里提取 WINE_PACKAGE_FLAGS 的模块列表。"""
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        txt = f.read()
    mods = []
    # 形如 WINE_PACKAGE_FLAGS(GSTREAMER,[gstreamer-1.0 gstreamer-video-1.0 ...]
    for m in re.finditer(r"WINE_PACKAGE_FLAGS\(\s*([A-Z0-9_]+)\s*,\s*\[([^\]]*)\]", txt):
        var, body = m.group(1), m.group(2)
        body = body.replace("\n", " ").strip()
        if body:
            mods.extend(body.split())
    return mods


# ------------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pc-dir", action="append", default=[],
                    help="pkgconfig 目录，可多次指定")
    ap.add_argument("--lib-dir", action="append", default=[],
                    help="库目录（判定 .so 实体），可多次指定")
    ap.add_argument("--require", default="",
                    help="逗号或空格分隔的入口模块")
    ap.add_argument("--from-configure-ac", default="",
                    help="从 configure.ac 自动提取入口模块")
    ap.add_argument("--skip-soname", action="store_true",
                    help="只查 .pc 闭包，不查 .so 实体")
    args = ap.parse_args()

    roots = []
    if args.require:
        roots.extend(re.split(r"[,\s]+", args.require.strip()))
    if args.from_configure_ac:
        try:
            roots.extend(modules_from_configure_ac(args.from_configure_ac))
        except OSError as e:
            print("⚠️ 读取 %s 失败: %s" % (args.from_configure_ac, e), file=sys.stderr)
    roots = [r for r in dict.fromkeys(roots) if r]

    if not roots:
        print("⚠️ 没有入口模块，跳过检查")
        return 0

    if not args.pc_dir:
        # 给一个合理的默认，方便手工跑
        args.pc_dir = [
            "/usr/aarch64-linux-gnu/lib/pkgconfig",
            "/usr/lib/aarch64-linux-gnu/pkgconfig",
            "/usr/share/pkgconfig",
        ]
    if not args.lib_dir:
        args.lib_dir = [
            "/usr/aarch64-linux-gnu/lib",
            "/usr/lib/aarch64-linux-gnu",
        ]

    idx = build_index(args.pc_dir)
    print("=== pkg-config 依赖闭包体检 ===")
    print("入口模块 (%d): %s" % (len(roots), " ".join(roots)))
    print("pc 目录: %s" % ":".join(args.pc_dir))
    print("可解析 .pc: %d 个" % len(idx))
    print()

    res = walk_closure(roots, idx)
    reachable, missing, edges = res["reachable"], res["missing"], res["edges"]

    print("可达模块: %d" % len(reachable))
    if missing:
        print()
        print("❌ 缺失的 .pc (%d):" % len(missing))
        for mod in sorted(missing):
            parents = ", ".join(sorted(edges.get(mod, []))) or "入口"
            print("    %-28s <- 由 %s 引入" % (mod, parents))
    else:
        print("✅ 全部 .pc 依赖可达")

    dangling = []
    libdir_ok = [d for d in args.lib_dir if os.path.isdir(d)]
    if not args.skip_soname and not libdir_ok:
        print()
        print("⚠️ .so 实体检查已跳过：--lib-dir 下的目录都不存在")
        print("   （目录: %s）" % ":".join(args.lib_dir))
    elif not args.skip_soname:
        pc_paths = [(m, idx[m]) for m in sorted(reachable)]
        dangling = check_sonames(pc_paths, libdir_ok)
        print()
        if dangling:
            print("❌ 不可用的 .so (%d):" % len(dangling))
            for mod, lib, tgt, why in dangling:
                extra = " -> %s" % tgt if tgt else ""
                print("    %-24s %-26s%s  (%s)" % (mod, lib, extra, why))
            print("    ⚠️ 注意：软链存在不等于可用，-dev 包常常只放软链，")
            print("       实体 .so.N 在独立的 runtime 包里，需要一并下载。")
        else:
            print("✅ 所有 -lXXX 都有可打开的 .so 实体")

    print()
    if missing or dangling:
        pkgs, unknown = suggest(missing, dangling)
        if pkgs:
            print("💡 建议补装的包（Debian/Ubuntu 命名）:")
            for pkg in sorted(pkgs):
                print("    %-40s 提供 %s" % (pkg, ", ".join(sorted(pkgs[pkg]))))
            print("    安装：apt-get install -y %s" % " ".join(sorted(pkgs)))
        if unknown:
            print("    ⚠️ 以下项不在内置映射表里，需手工确认：%s" % ", ".join(unknown))
            print("       可用 `dpkg -S <文件>` 或 `apt-file search <文件>` 反查包名。")
        print()
        print("结果: ❌ 失败")
        return 1
    print("结果: ✅ 通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""去掉 winegstreamer 的 GstGL 依赖（对齐 AndreRH / termux-glibc-mangohud）。

背景
----
wine 的 configure.ac 里 WINE_PACKAGE_FLAGS(GSTREAMER, [gstreamer-1.0
gstreamer-video-1.0 gstreamer-audio-1.0 gstreamer-tag-1.0 gstreamer-gl-1.0], ...)

其中 gstreamer-gl-1.0 属于 libgstreamer-plugins-base1.0-dev，它依赖 OpenGL/EGL
头与库。在 Termux/Android 交叉编译场景下：
  - gl.h/egl.h 可能缺失或版本不对
  - 即使 pkg-config 找到，链接时也可能因缺 GL 符号而失败
  - winegstreamer 实际只用了 3 个 GstGL 函数（display_new / create_context /
    add_context），且 Android 上本就无 GL display 可用

做法（与 mangohud 完全一致）
----
1) configure.ac: 把 `gstreamer-tag-1.0 gstreamer-gl-1.0` 改成 `gstreamer-tag-1.0`，
   从探测里去掉 gstreamer-gl-1.0。
2) dlls/winegstreamer/unixlib.c 与 wg_parser.c：把 `#include <gst/gl/gl.h>`
   替换成 GstGL 垫片（typedef + 3 个函数宏 + 类型宏），不再依赖真实头。
3) 删除 unixlib.c 里 setenv("GST_GL_WINDOW") 一行。
4) 自检：所有 gst_gl_* 符号与 GstGL* 类型必须被垫片覆盖，否则报错。

幂等。
用法: strip_gstgl.py <wine_source_root>
"""
import io
import os
import re
import sys

SHIM = (
    "typedef struct _GstGLDisplay GstGLDisplay;\n"
    "typedef struct _GstGLContext GstGLContext;\n"
    "#define gst_gl_display_new() (NULL)\n"
    "#define gst_gl_display_create_context(d, c, o, e) (0)\n"
    "#define gst_gl_display_add_context(d, c) ((void)0)\n"
    '#define GST_GL_DISPLAY_CONTEXT_TYPE "gst.gl.GLDisplay"\n'
    "#define gst_context_set_gl_display(c, d) ((void)0)"
)

ALLOWED_FN = {
    "gst_gl_display_new",
    "gst_gl_display_create_context",
    "gst_gl_display_add_context",
    "gst_gl_display_add_context",  # dup guard
}

ALLOWED_TYPE = {"GstGLDisplay", "GstGLContext"}


def note(msg):
    print("[gstgl] %s" % msg, flush=True)


def patch_configure_ac(root):
    p = os.path.join(root, "configure.ac")
    if not os.path.isfile(p):
        note("configure.ac 不存在，跳过")
        return
    s = io.open(p, encoding="utf-8", errors="surrogateescape").read()
    if "gstreamer-gl-1.0" not in s:
        note("configure.ac 已无 gstreamer-gl-1.0，跳过")
        return
    s = s.replace("gstreamer-tag-1.0 gstreamer-gl-1.0", "gstreamer-tag-1.0")
    io.open(p, "w", encoding="utf-8", errors="surrogateescape").write(s)
    note("configure.ac: 已去掉 gstreamer-gl-1.0")


def patch_shim(root):
    files = [
        "dlls/winegstreamer/unixlib.c",
        "dlls/winegstreamer/wg_parser.c",
    ]
    for rel in files:
        p = os.path.join(root, rel)
        if not os.path.isfile(p):
            continue
        s = io.open(p, encoding="utf-8", errors="surrogateescape").read()
        if "#include <gst/gl/gl.h>" in s and SHIM.split("\n")[0] not in s:
            s = s.replace("#include <gst/gl/gl.h>", SHIM, 1)
            io.open(p, "w", encoding="utf-8", errors="surrogateescape").write(s)
            note("%s: gst-gl 垫片已注入" % rel)

    # 删掉 setenv("GST_GL_WINDOW")
    p = os.path.join(root, "dlls/winegstreamer/unixlib.c")
    if os.path.isfile(p):
        s = io.open(p, encoding="utf-8", errors="surrogateescape").read()
        s2 = re.sub(r'^.*setenv\("GST_GL_WINDOW".*$', "", s, flags=re.M)
        if s2 != s:
            io.open(p, "w", encoding="utf-8", errors="surrogateescape").write(s2)
            note("unixlib.c: 已删除 setenv GST_GL_WINDOW")


def verify(root):
    bad = 0
    # 1) 不应再有真实 gst/gl/gl.h include
    for rel, _, files in os.walk(os.path.join(root, "dlls/winegstreamer")):
        for f in files:
            if not f.endswith(".c"):
                continue
            p = os.path.join(rel, f)
            s = io.open(p, encoding="utf-8", errors="surrogateescape").read()
            if "#include <gst/gl/gl.h>" in s:
                note("FAIL: %s 仍引用 gst/gl/gl.h" % p)
                bad = 1

    # 2) gst_gl_* 符号检查
    fn_pat = re.compile(r"\bgst_gl_[a-z_]+")
    type_pat = re.compile(r"\bGstGL[A-Za-z]+\b")
    for rel, _, files in os.walk(os.path.join(root, "dlls/winegstreamer")):
        for f in files:
            if not f.endswith(".c"):
                continue
            p = os.path.join(rel, f)
            s = io.open(p, encoding="utf-8", errors="surrogateescape").read()
            for ident in fn_pat.findall(s):
                if ident not in ALLOWED_FN:
                    note("MISS 函数 %s（未被垫片覆盖）" % ident)
                    bad = 1
            for t in type_pat.findall(s):
                if t not in ALLOWED_TYPE:
                    note("MISS 类型 %s（未定义）" % t)
                    bad = 1

    if bad:
        note("自检失败")
        return 1
    note("自检通过：无 gst/gl/gl.h 引用，GstGL 符号/类型全部被垫片覆盖")
    return 0


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: %s <wine_source_root>" % sys.argv[0])
    root = sys.argv[1].rstrip("/")
    patch_configure_ac(root)
    patch_shim(root)
    return verify(root)


if __name__ == "__main__":
    sys.exit(main())
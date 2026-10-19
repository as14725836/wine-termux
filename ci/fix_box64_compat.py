#!/usr/bin/env python3
"""
fix_box64_compat.py —— 幂等的 wine-box64-compat 结构化注入

背景：
  wine-box64-compat.patch 是按 wine-9.x/10.x 的行号写的，在 wine 11.x 上
  Hunk #1(函数定义) 必然 FAILED，Hunk #2(调用点) 却因 fuzz 命中，
  结果 virtual.c 里"有调用、无定义" —— 编译报
    implicit declaration of 'wine_emulator_detected'
    initialization of 'void *' from 'int' makes pointer from integer
  更糟的是 Hunk #2 落点漂到了 virtual_get_system_info()，语义也不对
  （必须在 virtual_init() 里、get_host_addr_space_limit() 之后生效）。

本脚本不依赖行号，按锚点做三件事：
  1) 在 host_addr_space_limit 声明后插入两个函数的定义（若缺失）
  2) 删除所有落在 virtual_init() 之外的同名 clamp 块（错位残留）
  3) 若 virtual_init() 内没有 clamp 块，插到
     host_addr_space_limit = get_host_addr_space_limit(); 之后

可重复执行；已正确时不产生任何改动。退出码 0=OK，3=自检失败。
"""
import io
import os
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "dlls/ntdll/unix/virtual.c"

DEFS = r'''
/***********************************************************************
 *           wine_emulator_detected
 *
 * Detect whether wine runs under an x86 emulator (box64 / box86 / FEX / qemu).
 * Such emulators translate the guest code and execute it inside their own
 * (host) address space, so every wine assumption based on host addresses
 * becomes invalid.
 *   WINE_EMULATOR=<name>     force on
 *   WINE_EMULATOR=0          force off (escape hatch)
 */
static int wine_emulator_detected(void)
{
    static int cached = -1;
    const char *env;

    if (cached >= 0) return cached;
    cached = 0;

    if ((env = getenv( "WINE_EMULATOR" )) && *env)
    {
        cached = (env[0] == '0' && !env[1]) ? 0 : 1;
        return cached;
    }
    if (getenv( "BOX64_VERSION" ) || getenv( "BOX64_LD_LIBRARY_PATH" ) || getenv( "BOX64_LOG" ) ||
        getenv( "BOX86_VERSION" ) || getenv( "BOX86_LD_LIBRARY_PATH" ) ||
        getenv( "FEX_TSOENABLED" ) || getenv( "FEX_ROOTFS" ) || getenv( "FEX_APP_CONFIG" ) ||
        getenv( "QEMU_LD_PREFIX" ) || getenv( "QEMU_CPU" ))
        cached = 1;
#ifdef __linux__
    if (!cached)
    {
        /* box64/box86/FEX keep the guest binary mapped in their own process,
         * so /proc/self/exe points at the emulator itself. */
        char buf[256];
        ssize_t len = readlink( "/proc/self/exe", buf, sizeof(buf) - 1 );
        if (len > 0)
        {
            buf[len] = 0;
            if (strstr( buf, "box64" ) || strstr( buf, "box86" ) ||
                strstr( buf, "FEXInterpreter" ) || strstr( buf, "qemu-" ))
                cached = 1;
        }
    }
#endif
    return cached;
}

/***********************************************************************
 *           wine_emulator_addr_space_limit
 *
 * Upper bound of the address space to use under an emulator. Defaults to the
 * same 39-bit safe window used by the 39-bit layout patches (512GB - 64KB),
 * overridable with WINE_EMULATOR_LIMIT=<hex|dec>.
 */
static void *wine_emulator_addr_space_limit(void)
{
    const char *env = getenv( "WINE_EMULATOR_LIMIT" );

    if (env && *env) return (void *)(ULONG_PTR)strtoull( env, NULL, 0 );
    return (void *)0x7fffff0000;
}

'''

CLAMP = '''    if (wine_emulator_detected())
    {
        void *limit = wine_emulator_addr_space_limit();

        address_space_limit = limit;
        user_space_limit    = limit;
        working_set_limit   = limit;
        host_addr_space_limit = limit;
        WARN( "box64/emu compat: address space limited to %p\\n", limit );
    }
'''

DEF_ANCHORS = [
    "static void *host_addr_space_limit;  /* top of the host virtual address space */\n",
    "static void *host_addr_space_limit;\n",
    "static void *address_space_start = (void *)0x10000;\n",
]


def log(msg):
    print("[box64-fix] " + msg)


def func_bounds(text, name):
    """返回 (start, end) 或 (-1, -1)。end 指向闭合 '}' 之后。"""
    i = text.find(name)
    if i < 0:
        return -1, -1
    m = re.compile(r"\n\}\n").search(text, i)
    return i, (m.end() if m else -1)


def main():
    if not os.path.isfile(PATH):
        log("FATAL: %s not found" % PATH)
        return 4

    src = io.open(PATH, encoding="utf-8", errors="surrogateescape").read()
    orig = src

    # ---- 1. 函数定义 ----
    if "static int wine_emulator_detected(void)" not in src:
        for a in DEF_ANCHORS:
            if a in src:
                src = src.replace(a, a + DEFS, 1)
                log("DEFS: inserted")
                break
        else:
            log("DEFS: ANCHOR-NOT-FOUND (fatal)")
            return 5
    else:
        log("DEFS: already present")

    # ---- 2. 清理 virtual_init 之外的错位 clamp ----
    vs, ve = func_bounds(src, "void virtual_init(void)")
    if vs < 0:
        log("virtual_init NOT FOUND (fatal)")
        return 6

    pat = re.compile(r"[ \t]*if \(wine_emulator_detected\(\)\)\r?\n.*?\n[ \t]*\}\r?\n", re.S)
    removed = 0
    for _ in range(10):
        vs, ve = func_bounds(src, "void virtual_init(void)")
        m = pat.search(src)
        if not m:
            break
        if vs <= m.start() <= ve:
            break  # 首个命中已在正确位置
        src = src[:m.start()] + src[m.end():]
        removed += 1
    log("CLAMP: removed misplaced = %d" % removed)

    # ---- 3. 在 virtual_init 内插入 clamp ----
    vs, ve = func_bounds(src, "void virtual_init(void)")
    body = src[vs:ve] if ve > vs > 0 else ""
    if "if (wine_emulator_detected())" in body:
        log("CLAMP: already inside virtual_init")
    else:
        anchor = "    host_addr_space_limit = get_host_addr_space_limit();\n"
        pos = src.find(anchor, vs)
        if pos < 0:
            log("CLAMP: ANCHOR-NOT-FOUND (fatal)")
            return 7
        after = pos + len(anchor)
        nl = src.find("\n", after)
        ins = after if nl < 0 else nl + 1
        if nl > 0 and "TRACE(" in src[after:nl]:
            ins = nl + 1
        src = src[:ins] + CLAMP + src[ins:]
        log("CLAMP: inserted into virtual_init")

    # ---- 写回 ----
    if src != orig:
        io.open(PATH, "w", encoding="utf-8", errors="surrogateescape").write(src)
        log("WRITE: changed")
    else:
        log("WRITE: unchanged")

    # ---- 自检 ----
    chk = io.open(PATH, encoding="utf-8", errors="surrogateescape").read()
    vs, ve = func_bounds(chk, "void virtual_init(void)")
    body = chk[vs:ve] if ve > vs > 0 else ""
    c_def = chk.count("static int wine_emulator_detected(void)")
    c_lim = chk.count("static void *wine_emulator_addr_space_limit(void)")
    c_call = chk.count("if (wine_emulator_detected())")
    in_vi = "if (wine_emulator_detected())" in body
    ok = (c_def == 1 and c_lim == 1 and c_call == 1 and in_vi)

    log("SELFCHECK %s (def=%d limit=%d call=%d in_virtual_init=%s)"
        % ("OK" if ok else "FAIL", c_def, c_lim, c_call, in_vi))
    return 0 if ok else 3


if __name__ == "__main__":
    sys.exit(main())
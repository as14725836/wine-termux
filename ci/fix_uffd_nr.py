#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""修复 wine-dwproton 的 uffd_tmp_defs.h 里 __NR_userfaultfd 的 aarch64 硬编码错误。

原文件：
    #ifdef __x86_64__
    #define __NR_userfaultfd 323
    #else
    #define __NR_userfaultfd 374      <-- aarch64 上是错的
    #endif

374 只在 x86_64 上是 userfaultfd；aarch64 上真正的编号是 282，
374 落在 [295...423] 保留区。

后果：kernel_writewatch_init() 里 syscall(374, ...)
  - 普通 Linux 内核：ENOSYS，wine 走 `if (uffd_fd == -1) return;` 正常跳过
  - Android：seccomp 直接 SIGSYS，进程当场被杀
      strace: syscall_0x176(0x80801, 0, 0x100022, ...) -> SIGSYS
              si_syscall=374, si_arch=AUDIT_ARCH_AARCH64
              +++ killed by SIGSYS +++

幂等：以 WINE_TERMUX_NR_FIXED 为标记。
用法: fix_uffd_nr.py <uffd_tmp_defs.h> [--dry-run]
"""
import io
import os
import re
import sys

MARK = "WINE_TERMUX_NR_FIXED"

NEW = """/* %s */
/* 原实现把非 x86_64 分支写死成 374，但 aarch64 的 __NR_userfaultfd 是 282
 * （374 落在 [295...423] 保留区）。Android seccomp 对未知 syscall 直接
 * SIGSYS 杀进程，导致 wine 在 virtual_init 阶段就 Bad signal / Bad system call。
 * 这里优先使用 sys/syscall.h 的正确值，仅在缺失时按架构兜底。 */
#ifndef __NR_userfaultfd
# if defined(__x86_64__)
#  define __NR_userfaultfd 323
# elif defined(__aarch64__)
#  define __NR_userfaultfd 282
# elif defined(__arm__)
#  define __NR_userfaultfd 388
# else
#  define __NR_userfaultfd 374
# endif
#endif""" % MARK

PAT = re.compile(
    r'#ifdef\s+__x86_64__\s*\n'
    r'#\s*define\s+__NR_userfaultfd\s+323\s*\n'
    r'#else\s*\n'
    r'#\s*define\s+__NR_userfaultfd\s+374\s*\n'
    r'#endif')


def note(msg):
    print("[uffd-nr] %s" % msg, flush=True)


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: %s <uffd_tmp_defs.h> [--dry-run]" % sys.argv[0])
    path = sys.argv[1]
    dry = "--dry-run" in sys.argv

    if not os.path.isfile(path):
        note("SKIP: %s 不存在" % path)
        return 0

    src = io.open(path, "r", encoding="utf-8", errors="surrogateescape").read()

    if MARK in src:
        note("已修复过，跳过")
        return 0

    m = PAT.search(src)
    if not m:
        note("WARN: 未匹配到 __NR_userfaultfd 硬编码片段")
        note("      该树可能已自行修正，或写法不同")
        return 0

    note("找到硬编码片段: %r ..." % m.group(0).split("\n")[0])
    new_src = src[:m.start()] + NEW + src[m.end():]

    if dry:
        note("dry-run: 将替换 %d 字节" % len(m.group(0)))
        return 0

    io.open(path, "w", encoding="utf-8", errors="surrogateescape").write(new_src)
    note("已改为架构自适应（aarch64 -> 282）")
    return 0


if __name__ == "__main__":
    sys.exit(main())
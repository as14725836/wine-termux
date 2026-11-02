#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""禁用 wine 的 userfaultfd writewatch，避免 Android seccomp SIGSYS。

背景
----
wine-dwproton 的 dlls/ntdll/unix/virtual.c 里 kernel_writewatch_init()：

    uffd_fd = syscall( __NR_userfaultfd, O_CLOEXEC | O_NONBLOCK | UFFD_USER_MODE_ONLY );
    if (uffd_fd == -1) return;

而 uffd_tmp_defs.h 把非 x86_64 分支写死成 374（aarch64 真正值是 282，
374 落在 [295...423] 保留区）。于是：

  - 普通 Linux 内核：返回 ENOSYS，wine 走 -1 分支，正常跳过
  - Android：seccomp 对未知 syscall 直接 SIGSYS，进程当场被杀
      strace: syscall_0x176(0x80801, 0, 0x100022, ...) -> SIGSYS
              si_syscall=374, si_arch=AUDIT_ARCH_AARCH64
              +++ killed by SIGSYS +++

做法
----
直接把整个调用替换成 `uffd_fd = -1;`，让 wine 走"不支持"分支。
比修正编号更稳：部分 Android 内核即使编号正确也禁止 userfaultfd。

幂等，以 Termux marker 识别。
用法: disable_uffd.py <virtual.c> [--dry-run]
"""
import io
import os
import re
import sys

MARK = "Termux: userfaultfd disabled"

# 匹配（可能跨行到分号）的 uffd_fd = syscall( __NR_userfaultfd ... );
PAT = re.compile(
    r'^([ \t]*)uffd_fd[ \t]*=[ \t]*syscall[ \t]*\([ \t]*__NR_userfaultfd\b[^;]*;',
    re.M)


def note(msg):
    print("[uffd] %s" % msg, flush=True)


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: %s <virtual.c> [--dry-run]" % sys.argv[0])
    path = sys.argv[1]
    dry = "--dry-run" in sys.argv

    if not os.path.isfile(path):
        note("SKIP: %s 不存在" % path)
        return 0

    src = io.open(path, "r", encoding="utf-8", errors="surrogateescape").read()

    m = PAT.search(src)
    if not m:
        if MARK in src:
            note("已禁用过，跳过")
        else:
            note("未找到 uffd_fd = syscall(__NR_userfaultfd ...)，无需处理")
        return 0

    indent = m.group(1)
    repl = "%suffd_fd = -1; /* %s, avoid SIGSYS */" % (indent, MARK)
    new_src = src[:m.start()] + repl + src[m.end():]

    if dry:
        note("dry-run: 将替换为 %r" % repl.strip())
        return 0

    io.open(path, "w", encoding="utf-8", errors="surrogateescape").write(new_src)
    note("已禁用 userfaultfd writewatch")
    return 0


if __name__ == "__main__":
    sys.exit(main())
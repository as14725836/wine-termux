#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
strict_patch.py — 注入脚本"必须命中"断言工具

背景
----
历史上 ci/patches/wow64/ 下的脚本在上游代码变更后会出现**静默失效**：
锚点找不到 → 打一行 WARN → return 0 → 构建照常变绿，但补丁实际没生效。
最典型的一次是 ci/strip_gstgl.py：文件被删后 GSTGL_PY 为空，
整个步骤只 WARN 不报错，导致多轮构建"看起来 strip 了"其实没有。

用法
----
    from strict_patch import PatchStatus, finish

    st = PatchStatus("gst-no-gl")
    ...
    st.applied("unix_private.h extern 已注入")
    st.idempotent("已含 wine_gst_no_gl")   # 幂等跳过，不算失败
    ...
    sys.exit(finish(st))

结果语义
--------
  APPLIED    本次成功注入        → 通过
  IDEMPOTENT 之前已注入过        → 通过
  SKIP       该树确实不需要此补丁 → 通过（例如上游已无对应机制）
  MISSING    应该注入但锚点没了   → **失败**（除非 STRICT_PATCH=0）
  ERROR      读写/py 异常         → **失败**

STRICT_PATCH 环境变量
---------------------
  未设置或 =1  → 严格模式（默认）。只要出现 MISSING/ERROR 就以非零退出。
  =0           → 宽松模式，仅打印警告、仍返回 0（旧行为，用于排障）。
"""

import os
import sys

EXIT_OK = 0
EXIT_FAIL = 1

APPLIED = "APPLIED"
IDEMPOTENT = "IDEMPOTENT"
SKIP = "SKIP"
MISSING = "MISSING"
ERROR = "ERROR"

_FAIL_KINDS = (MISSING, ERROR)


def strict_enabled():
    """严格模式默认开启，只有显式 STRICT_PATCH=0/false/no/off 才关闭。"""
    v = os.environ.get("STRICT_PATCH", "1").strip().lower()
    return v not in ("0", "false", "no", "off")


class PatchStatus(object):
    """收集单个注入脚本里各个锚点的处理结果。"""

    def __init__(self, name):
        self.name = name
        self.records = []
        self._failures = []

    def applied(self, msg):
        self._add(APPLIED, msg)

    def idempotent(self, msg):
        self._add(IDEMPOTENT, msg)

    def skip(self, msg):
        """该树不需要此补丁 —— 属于正常情况。"""
        self._add(SKIP, msg)

    def missing(self, msg):
        """该注入却找不到锚点 —— 上游可能已改代码。"""
        self._add(MISSING, msg)

    def error(self, msg):
        self._add(ERROR, msg)

    def _add(self, kind, msg):
        self.records.append((kind, msg))
        tag = {
            APPLIED: "OK  ",
            IDEMPOTENT: "skip",
            SKIP: "skip",
            MISSING: "MISS",
            ERROR: "ERR ",
        }[kind]
        print("[%s] %s: %s" % (self.name, tag, msg), flush=True)
        if kind in _FAIL_KINDS:
            self._failures.append(msg)

    @property
    def failures(self):
        return list(self._failures)

    @property
    def has_failure(self):
        return bool(self._failures)

    def count(self, kind):
        return sum(1 for k, _ in self.records if k == kind)

    def summary(self):
        parts = []
        for kind, label in ((APPLIED, "applied"),
                            (IDEMPOTENT, "idempotent"),
                            (SKIP, "skipped"),
                            (MISSING, "missing"),
                            (ERROR, "error")):
            n = self.count(kind)
            if n:
                parts.append("%s=%d" % (label, n))
        return ", ".join(parts) if parts else "no-op"


def finish(st):
    """在 main() 末尾调用，返回进程退出码。"""
    strict = strict_enabled()
    if st.has_failure:
        if strict:
            print("[%s] FAIL (strict): %s" %
                  (st.name, "; ".join(st.failures)), file=sys.stderr)
            print("[%s]   上游代码可能已变更，补丁锚点失效。" % st.name, file=sys.stderr)
            print("[%s]   请更新 ci/patches/wow64/ 下对应脚本；" % st.name, file=sys.stderr)
            print("[%s]   排障期间可设 STRICT_PATCH=0 临时放行。" % st.name, file=sys.stderr)
            return EXIT_FAIL
        print("[%s] WARN: 锚点失效但 STRICT_PATCH=0，按宽松模式放行: %s"
              % (st.name, "; ".join(st.failures)), file=sys.stderr)
        return EXIT_OK
    print("[%s] OK: %s" % (st.name, st.summary()), flush=True)
    return EXIT_OK


def read_text(st, path):
    try:
        with open(path, "r", encoding="utf-8", errors="surrogateescape") as f:
            return f.read()
    except OSError as e:
        st.error("读取 %s 失败: %s" % (path, e))
        return None


def write_text(st, path, text):
    try:
        with open(path, "w", encoding="utf-8", errors="surrogateescape") as f:
            f.write(text)
        return True
    except OSError as e:
        st.error("写入 %s 失败: %s" % (path, e))
        return False

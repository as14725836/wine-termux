#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Disable tools/make_makefiles when building a custom (non-upstream) wine source.

Why: TkG runs tools/make_makefiles unconditionally.  That script walks every
*.idl and does ``die "no makedep flags specified in <file>"`` unless the file
declares a ``#pragma makedep`` flag.  Forks such as dwproton keep idl files
that are never fed through widl (exactly the situation TkG already special
cases for *ValveSoftware* trees), so the check aborts the build with e.g.:

    no makedep flags specified in dlls/amd_ags_x64/dxvk_interfaces.idl
    at tools/make_makefiles line 270.

Fix: extend the existing skip condition so it also skips when
``_custom_wine_source`` is non-empty.

Usage:  tkg_skip_makemakefiles.py /path/to/wine-tkg-git
Idempotent: re-running is a no-op.
"""

import os
import sys

MARKER = "termux_skip_makemakefiles"

OLD = (
    'if [[ "$_custom_wine_source" != *"ValveSoftware"* ]]; then\n'
    '\t  git add * && true\n'
    '\t  tools/make_makefiles\n'
    '\tfi'
)

NEW = (
    '# ' + MARKER + ': custom source (dwproton etc.) does not run make_makefiles\n'
    'if [[ "$_custom_wine_source" != *"ValveSoftware"* ]] && [ -z "$_custom_wine_source" ]; then\n'
    '\t  git add * && true\n'
    '\t  tools/make_makefiles\n'
    '\tfi'
)


def main():
    if len(sys.argv) < 2:
        print("[makemakefiles] usage: tkg_skip_makemakefiles.py <wine-tkg-git dir>")
        return 0

    path = os.path.join(sys.argv[1], "wine-tkg-scripts", "prepare.sh")
    if not os.path.isfile(path):
        print("[makemakefiles] prepare.sh not found: %s -> skip" % path)
        return 0

    with open(path, encoding="utf-8") as f:
        src = f.read()

    if MARKER in src:
        print("[makemakefiles] already applied -> skip")
        return 0

    if OLD not in src:
        print("[makemakefiles] WARN: make_makefiles block not matched -> skip")
        return 0

    with open(path, "w", encoding="utf-8") as f:
        f.write(src.replace(OLD, NEW, 1))

    print("[makemakefiles] OK: tools/make_makefiles disabled for custom wine source")
    return 0


if __name__ == "__main__":
    sys.exit(main())

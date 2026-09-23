#!/data/data/com.termux/files/usr/bin/bash
# ci/import_name_fallback.sh -- 让 wine 的 PE 导入名支持非 ASCII（GBK/SJIS/Big5...）名字
#
# 背景：wine 的 build_import_name() 对 PE 导入名只做 Latin-1 逐字节直扩
#       （dlls/ntdll/ntdll_misc.h: ascii_to_unicode()），与 locale / 系统代码页无关。
#       所以当 DLL 的 PE 导入名是 GBK 等编码、而 Unix 侧文件名是 UTF-8 时，
#       wine 会去找一个“乱码名”，永远找不到：
#         err:module:import_dll Library ... not found
#         err:module:loader_init ... status c0000135
# 本补丁在 import_dll() 里加“按常见东亚代码页重试”的回退。
#
# 用法： source ci/import_name_fallback.sh && _termux_import_name_fix /path/to/wine/src
#        或直接：bash ci/import_name_fallback.sh /path/to/wine/src

if ! command -v warning >/dev/null 2>&1; then
    warning() { echo "warning: $*" >&2; }
fi

_termux_import_name_fix() {
    local _src="${1:-${srcdir}/${_winesrcdir}}"
    local _file="$_src/dlls/ntdll/loader.c"
    local _patch="${CI_DIR:-/tmp/ci}/wine_import_name_cp_fallback.patch"

    if [ ! -f "$_file" ]; then warning "import-name fix: 找不到 $_file"; return 0; fi
    if grep -q 'convert_import_name' "$_file"; then warning "import-name fix: 已应用，跳过"; return 0; fi
    if [ ! -f "$_patch" ]; then warning "import-name fix: 缺少 $_patch"; return 0; fi

    cp -f "$_file" "$_file.before_import_fix"

    if ! patch -p1 -d "$_src" --dry-run < "$_patch" >/dev/null 2>&1; then
        warning "import-name fix: dry-run 失败（上游已变？），SKIP"
        return 0
    fi

    if ! patch -p1 -d "$_src" < "$_patch" >/dev/null; then
        warning "import-name fix: 应用失败，回滚"
        cp -f "$_file.before_import_fix" "$_file"
        return 0
    fi

    echo "  import-name fix: 已应用（convert_import_name 标记 $(grep -c 'convert_import_name' "$_file") 处）"
    grep -n 'codepages\[\] = ' "$_file" | head -1
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    _termux_import_name_fix "$@"
fi

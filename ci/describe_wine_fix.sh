########################################################################
# CI override: _describe_wine / _describe_other (tolerant for tagless tree)
#
# 背景：
#   brunodev85/wine-10.10-custom 没有任何 git tag（tags 数量 = 0）。
#   TkG 的 _describe_wine() 直接调用：
#       git describe --long --tags | sed ...
#   在无 tag 的树上该命令失败（"fatal: No names found, cannot describe anything."）。
#   non-makepkg-build.sh 顶部是 `set -e`，于是 prepare 完成后
#   build_wine_tkg -> pkgver=$(pkgver) -> _describe_wine 一失败，脚本立刻退出，
#   EXIT trap 打印 "=> exit cleanup done"，configure / make 从未执行，
#   /tmp/output 不存在 -> 外层 `cd /tmp/output/` 失败 -> 整个构建失败。
#
# 修复：
#   同文件内后定义者胜，这里在 prepare.sh 末尾追加容错版。
########################################################################

_describe_wine() {
  if [ -e "$_where"/temp ]; then
    source "$_where"/temp
  fi

  local _desc=""

  if [ "$_LOCAL_PRESET" = "valve-exp-bleeding" ]; then
    _desc="$_bleeding_tag"
  else
    _desc="$(git describe --long --tags 2>/dev/null)" || \
      _desc="$(git describe --long --tags --always 2>/dev/null)" || \
      _desc=""
  fi

  if [ -z "$_desc" ]; then
    local _fallback="${_plain_version:-}"
    [ -n "$_fallback" ] || _fallback="wine-10.10"
    local _sha
    _sha="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
    _desc="${_fallback}-nogit-${_sha}"
    msg2 "CI: _describe_wine fallback (tagless tree) -> ${_desc}"
  fi

  if [ "$_LOCAL_PRESET" = "valve-exp-bleeding" ]; then
    if [ "$_ismakepkg" = "true" ]; then
      echo "$_desc" | sed 's/\([^-]*-g\)/r\1/;s/-/./g;s/^v//;s/\.rc/rc/;s/^wine\.//;s/\.wine//' | cut -d'.' -f1-7 | sed 's/experimental.//;s/bleeding.edge.//'
    else
      echo "$_desc" | sed 's/\([^-]*-g\)/r\1/;s/-/./g;s/^v//;s/\.rc/rc/;s/^wine\.//;s/\.wine//' | cut -d'.' -f1-7
    fi
  else
    if [ "$_ismakepkg" = "true" ]; then
      echo "$_desc" | sed 's/\([^-]*-g\)/r\1/;s/-/./g;s/^v//;s/\.rc/rc/;s/^wine\.//;s/experimental.//'
    else
      echo "$_desc" | sed 's/\([^-]*-g\)/r\1/;s/-/./g;s/^v//;s/\.rc/rc/;s/^wine\.//'
    fi
  fi
}

_describe_other() {
  local _desc=""
  _desc="$(git describe --long --tags --always 2>/dev/null)" || _desc=""
  if [ -z "$_desc" ]; then
    _desc="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
    msg2 "CI: _describe_other fallback -> ${_desc}"
  fi
  echo "$_desc" | sed 's/\([^-]*-g\)/r\1/;s/-/./g;s/^v//'
}

########################################################################
# 给源码树打一个本地 tag，让后续所有 git describe 调用（含 configure
# 生成、以及 TkG 其它位置）都能直接成功，属于双保险。
########################################################################
_ci_ensure_wine_tag() {
  local _src="${srcdir}/${_winesrcdir}"
  [ -d "$_src/.git" ] || return 0
  if ! git -C "$_src" describe --long --tags >/dev/null 2>&1; then
    local _tag="${_plain_version:-wine-10.10}"
    _tag="$(printf '%s' "$_tag" | tr -c 'A-Za-z0-9._-' '-')"
    [ -n "$_tag" ] || _tag="wine-10.10"
    git -C "$_src" tag -f "$_tag" >/dev/null 2>&1 || true
    msg2 "CI: created local tag '${_tag}' on tagless wine tree"
  fi
}

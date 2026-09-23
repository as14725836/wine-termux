# CI fix: 自定义 fork 的 git history 不完整
#   -> TkG 的 `git merge-base --is-ancestor 0c249e61... HEAD` 检测会失败，于是它选了旧布局的
#      libs/wine/Makefile.in（这个树里根本不存在），后面的 sed 报 "can't read" 并中止构建。
#   改为：哪个候选文件存在且含 git describe 就用哪个（wine10.10 的正确文件是 configure.ac / wine_srcdir）
for _cand in "${srcdir}/${_winesrcdir}/configure.ac:wine_srcdir" \
              "${srcdir}/${_winesrcdir}/libs/wine/Makefile.in:top_srcdir" \
              "${srcdir}/${_winesrcdir}/Makefile.in:srcdir"; do
  _p="${_cand%%:*}"
  _s="${_cand##*:}"
  if [ -e "$_p" ] && grep -q 'git describe' "$_p" 2>/dev/null; then
    _versioning_path="$_p"
    _versioning_string="$_s"
    break
  fi
done
warning "CI: versioning path=$_versioning_path (string=${_versioning_string})"

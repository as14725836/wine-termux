  ########################################################
  # CI override: hotfixer() (tolerant for custom tree)
  ########################################################
  hotfixer() {
    for _f in "${_hotfixes[@]}"; do
      if [ -e "${_f}.${_userpatch_ext}revert" ]; then
        msg2 "## Applying reverting hotfix for ${_userpatch_target}: ${_f##*/}.${_userpatch_ext}revert"
        echo -e "\nApplying reverting hotfix ${_f##*/wine-tkg-git/}.${_userpatch_ext}revert" >> "$_where"/prepare.log
        if patch -Np1 -R --dry-run < "${_f}.${_userpatch_ext}revert" >> "$_where"/prepare.log 2>&1; then
          if patch -Np1 -R < "${_f}.${_userpatch_ext}revert" >> "$_where"/prepare.log 2>&1; then
echo "Applied reverting hotfix ${_f##*/}.${_userpatch_ext}revert" >> "$_where"/last_build_config.log
          else
warning "SKIP revert hotfix ${_f##*/}.${_userpatch_ext}revert (failed)"
          fi
        else
          echo -e "\n${_f##*/}: REVERT HOTFIX SKIPPED (does not apply)" >> "$_where"/prepare.log
          warning "SKIP revert hotfix ${_f##*/}.${_userpatch_ext}revert (does not apply on custom tree)"
        fi
      fi
    done
    for _f in "${_hotfixes[@]}"; do
      if [ -e "${_f}.${_userpatch_ext}patch" ]; then
        msg2 "## Applying hotfix for ${_userpatch_target}: ${_f##*/}.${_userpatch_ext}patch"
        echo -e "\nApplying hotfix ${_f##*/wine-tkg-git/}.${_userpatch_ext}patch" >> "$_where"/prepare.log
        if patch -Np1 --dry-run < "${_f}.${_userpatch_ext}patch" >> "$_where"/prepare.log 2>&1; then
          if patch -Np1 < "${_f}.${_userpatch_ext}patch" >> "$_where"/prepare.log 2>&1; then
echo "Applied hotfix ${_f##*/}.${_userpatch_ext}patch" >> "$_where"/last_build_config.log
          else
warning "SKIP hotfix ${_f##*/}.${_userpatch_ext}patch (failed)"
          fi
        else
          echo -e "\n${_f##*/}: HOTFIX SKIPPED (hunks do not apply)" >> "$_where"/prepare.log
          warning "SKIP hotfix ${_f##*/}.${_userpatch_ext}patch (hunks do not apply on custom tree)"
        fi
      fi
    done
  }

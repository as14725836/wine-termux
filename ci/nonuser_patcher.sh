  ########################################################
  # CI override: nonuser_patcher (tolerant for custom tree)
  ########################################################
  nonuser_patcher() {
    if [ "$_NUKR" != "debug" ] || [[ "$_DEBUGANSW1" =~ [yY] ]]; then
      if [ "$_nopatchmsg" != "true" ]; then
        _fullpatchmsg=" -- ( $_patchmsg )"
      fi
      msg2 "Applying ${_patchname}"
      echo -e "\n${_patchname}${_fullpatchmsg}" >>"$_where"/prepare.log
      local _f=""
      if [ -n "$_patchpath" ]; then
        if [ -f "${_patchpath%/*}"/mainline/"$_patchname" ] || [ -f "${_patchpath%/*}"/mainline/legacy/"$_patchname" ]; then
          _patchpath="${_patchpath%/*}/mainline/"
        elif [ -f "${_patchpath%/*}"/staging/"$_patchname" ] || [ -f "${_patchpath%/*}"/staging/legacy/"$_patchname" ]; then
          _patchpath="${_patchpath%/*}/staging/"
        fi
        if [ -e "${_patchpath%/*}"/"$_patchname" ]; then
          _f="${_patchpath%/*}"/"$_patchname"
        elif [ -e "${_patchpath%/*}"/legacy/"$_patchname" ]; then
          _f="${_patchpath%/*}"/legacy/"$_patchname"
        elif [ -e "${_patchpath}"/legacy/"$_patchname" ]; then
          _f="${_patchpath}"/legacy/"$_patchname"
        elif [ -e "$_where"/"$_patchname" ]; then
          warning "Falling back to root dir patching"
          _f="$_where"/"$_patchname"
        fi
      elif [ -e "$_where"/"$_patchname" ]; then
        _f="$_where"/"$_patchname"
      fi
      if [ -z "$_f" ]; then
        warning "Patch not found -- Skipping"
        return 0
      fi
      if patch -Np1 --dry-run <"$_f" >>"$_where"/prepare.log 2>&1; then
        if patch -Np1 <"$_f" >>"$_where"/prepare.log 2>&1; then
          echo -e "${_patchname}${_fullpatchmsg}" >>"$_where"/last_build_config.log
        else
          echo -e "\n${_patchname}: APPLY FAILED - SKIPPED" >>"$_where"/prepare.log
          warning "SKIP ${_patchname} (apply failed)"
        fi
      else
        echo -e "\n${_patchname}: HUNKS DO NOT APPLY / already applied - SKIPPED${_fullpatchmsg}" >>"$_where"/prepare.log
        warning "SKIP ${_patchname} (hunks do not apply on custom tree)"
      fi
    fi
  }

  user_patcher() {
    local _patches=("$_where"/*."${_userpatch_ext}revert")
    if [ ${#_patches[@]} -ge 2 ] || [ -e "${_patches}" ]; then
      if [ "$_user_patches_no_confirm" != "true" ]; then
        msg2 "Found ${#_patches[@]} 'to revert' userpatches for ${_userpatch_target}:"
        printf '%s\n' "${_patches[@]}"
        read -rp "Do you want to install it/them? - Be careful with that ;)"$'\n> N/y : ' _CONDITION;
      fi
      if [[ "$_CONDITION" =~ [yY] ]] || [ "$_user_patches_no_confirm" = "true" ]; then
        for _f in ${_patches[@]}; do
          if [ -e "${_f}" ]; then
            msg2 "Reverting your own ${_userpatch_target} patch ${_f##*/}"
            echo -e "\nReverting your own patch ${_f##*/}" >> "$_where"/prepare.log
            if patch -Np1 -R --dry-run < "${_f}" >> "$_where"/prepare.log 2>&1; then
              if patch -Np1 -R < "${_f}" >> "$_where"/prepare.log 2>&1; then
                echo -e "Reverted your own patch ${_f##*/}" >> "$_where"/last_build_config.log
              else
                warning "SKIP revert ${_f##*/} (failed)"
              fi
            else
              echo -e "\n${_f##*/}: REVERT SKIPPED (does not apply)" >> "$_where"/prepare.log
              warning "SKIP revert ${_f##*/} (does not apply on custom tree)"
            fi
          fi
        done
      fi
    fi

    _patches=("$_where"/*."${_userpatch_ext}patch")
    if [ ${#_patches[@]} -ge 2 ] || [ -e "${_patches}" ]; then
      if [ "$_user_patches_no_confirm" != "true" ]; then
        msg2 "Found ${#_patches[@]} userpatches for ${_userpatch_target}:"
        printf '%s\n' "${_patches[@]}"
        read -rp "Do you want to install it/them? - Be careful with that ;)"$'\n> N/y : ' _CONDITION;
      fi
      if [[ "$_CONDITION" =~ [yY] ]] || [ "$_user_patches_no_confirm" = "true" ]; then
        for _f in ${_patches[@]}; do
          if [ -e "${_f}" ]; then
            msg2 "Applying your own ${_userpatch_target} patch ${_f##*/}"
            echo -e "\nApplying your own patch ${_f##*/}" >> "$_where"/prepare.log
            if patch -Np1 --dry-run < "${_f}" >> "$_where"/prepare.log 2>&1; then
              if patch -Np1 < "${_f}" >> "$_where"/prepare.log 2>&1; then
                echo -e "Applied your own patch ${_f##*/}" >> "$_where"/last_build_config.log
              else
                warning "SKIP ${_f##*/} (apply failed)"
              fi
            else
              echo -e "\n${_f##*/}: SKIPPED (hunks do not apply)" >> "$_where"/prepare.log
              warning "SKIP ${_f##*/} (hunks do not apply on custom tree)"
            fi
          fi
        done
      fi
    fi
  }

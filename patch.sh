#!/bin/bash
export script_dir="$(dirname $(readlink -f "$0"))"

# ========== 应用自定义补丁（根据 PATCH_SOURCE 变量，二选一） ==========
apply_custom_patches() {
    echo "=== 应用自定义补丁 ==="
    
    # 检查 PATCH_SOURCE 变量
    local patch_dir=""
    case "${PATCH_SOURCE:-none}" in
        "patch")
            patch_dir="$script_dir/patch"
            echo "📁 选择补丁目录: patch/"
            ;;
        "patch11.16")
            patch_dir="$script_dir/patch11.16"
            echo "📁 选择补丁目录: patch11.16/"
            ;;
        "none"|"")
            echo "ℹ️  未选择补丁目录 (PATCH_SOURCE=none)，跳过自定义补丁"
            return 0
            ;;
        *)
            echo "⚠️  未知的补丁目录: ${PATCH_SOURCE}，跳过"
            return 0
            ;;
    esac
    
    # 检查目录是否存在
    if [ ! -d "$patch_dir" ]; then
        echo "⚠️  补丁目录不存在: $patch_dir"
        return 0
    fi
    
    # 统计补丁数量
    local patch_count=$(ls -1 "$patch_dir"/*.patch 2>/dev/null | wc -l)
    if [ "$patch_count" -eq 0 ]; then
        echo "⚠️  目录中没有找到 .patch 文件: $patch_dir"
        return 0
    fi
    
    echo "找到 $patch_count 个补丁文件"
    
    # 按顺序应用所有补丁
    for patch_file in "$patch_dir"/*.patch; do
        if [ -f "$patch_file" ]; then
            local patch_name=$(basename "$patch_file")
            echo "  应用补丁: $patch_name"
            if patch -p1 < "$patch_file" 2>&1; then
                echo "  ✅ $patch_name 应用成功"
            else
                echo "  ⚠️  $patch_name 应用失败（跳过）"
            fi
        fi
    done
    
    echo "=== 自定义补丁应用完成 ==="
}
# ===========================================================

proton_apply_patch() {
  if [[ -d $script_dir/$1/$2 ]]; then
    . $script_dir/$1/$2/___patch___.conf $3
    echo "${patchFileArry[@]}"
    [[ ! -z ${patchFileArry[@]} ]] || exit 1
    for i in "${patchFileArry[@]}"; do
      [[ -f $script_dir/$1/$2/$i ]] || exit 1
      echo "Apply $1/$2/$i"
      if ! patch -p1 <$script_dir/$1/$2/$i; then
        echo "Apply $i for $1/$2 failed"
        return 1
      fi
    done
  else
    echo "Not Version Patch files=>$1/$2"
  fi
}

wine_apply_patch() {
  if [[ -d $script_dir/$1 ]]; then
    . $script_dir/$1/___patch___.conf $2
    echo "${patchFileArry[@]}"
    [[ ! -z ${patchFileArry[@]} ]] || exit 1
    for i in "${patchFileArry[@]}"; do
      [[ -f $script_dir/$1/$i ]] || exit 1
      echo "Apply $1/$i"
      if ! patch -p1 <$script_dir/$1/$i; then
        echo "Apply $i for $1 failed"
        return 1
      fi
    done
  else
    echo "Not Patch files=>$1"
  fi
}

copy_patches() {
  if [[ -d $script_dir/$1 ]]; then
    . $script_dir/$1/___patch___.conf $2
    echo "${patchFileArry[@]}"
    [[ ! -z ${patchFileArry[@]} ]] || exit 1
    for i in "${patchFileArry[@]}"; do
      [[ -f $script_dir/$1/$i ]] || exit 1
      echo "Copy $1/$i to $3"
      cp $script_dir/$1/$i $3/
    done
  else
    echo "Not Patch files=>$1"
  fi
}

add_tkg_mfdxgi() {
  if [[ -z $ENABLE_PROTON_MF ]] || [[ $ENABLE_PROTON_MF == false ]] || [[ $ENABLE_PROTON_MF == 0 ]]; then

    ver=$2 # 10.14
    major_ver=$(echo "$ver" | cut -d. -f1)
    minor_ver=$(echo "$ver" | cut -d. -f2)

    echo "mfdxgi: Add env '\$WINE_DO_NOT_CREATE_DXGI_DEVICE_MANAGER' only (no full proton mf patch)"

    if [ "$major_ver" -eq 9 ]; then
      cp "$script_dir/wine9_do_not_create_dxgi_device_manager.patch" $3/wine9_do_not_create_dxgi_device_manager.mylatepatch || exit 1
    elif [ "$major_ver" -ge 10 ] && [ "$minor_ver" -ge 4 ]; then
      cp "$script_dir/wine_do_not_create_dxgi_device_manager2.patch" $3/wine_do_not_create_dxgi_device_manager2.mylatepatch || exit 1
    else
      echo "error"
    fi
  fi
}

case $1 in
proton) 
    proton_apply_patch proton $2 || exit 1
    apply_custom_patches
    ;;
wine-tkg) 
    wine_apply_patch wine-tkg-git-staging-ge $2 || exit 1
    add_tkg_mfdxgi
    apply_custom_patches
    ;;
wine-tlg-auto) 
    copy_patches wine-tkg-git-staging-ge $2 $3 || exit 1
    add_tkg_mfdxgi
    apply_custom_patches
    ;;
esac

file_path=$2
# 归一化：允许传入裸版本号（11.20），自动补 wine- 前缀
case "$1" in
  wine-*) : ;;
  [0-9]*) set -- "wine-$1" "${@:2}" ;;
esac
sed2() {
  local file="$file_path2"
  local key="$1"
  local value="$2"

  if [[ -f "$file" ]]; then
    sed -i "s|^${key}=\"[^\"]*\"|${key}=\"${value}\"|" "$file" || exit 1
  else
    echo "File not found: $file"
    return 1
  fi
}

if [[ $1 =~ wine-([0-9]+)\.([0-9]+) ]]; then
  main_ver="${BASH_REMATCH[1]}"
  sub_ver="${BASH_REMATCH[2]}"
else
  echo "Illegal version number"
  exit 1
fi

file_path2="$file_path/customization.cfg"
if (( main_ver < 10 || (main_ver == 10 && sub_ver <= 16) )); then
  echo "Have esync & fsync ✅"
  sed2 _use_esync true
  sed2 _use_fsync true
else
  echo "No esync & fsync ❌"
  sed2 _use_esync false
  sed2 _use_fsync false
fi

sed2 _GE_WAYLAND false
sed2 _plain_version $1
sed2 _staging_version "v$(echo $1 | sed 's/^wine-//')"

# ===================== 自定义 Wine 源（dwproton 等 fork）=====================
# 用法：set-tkg-cfg.sh <wine_tag> <tkg_dir> <wine_source_url> <source_ref>
#   wine_source_url 非空时：
#     - _custom_wine_source 指向该仓库，TkG 会 mirror clone 成 src/<派生目录名>
#     - 强制 _use_staging=false（自定义源里没有 wine-staging 的 patch 基线，
#       且 TkG 的 _prepare 会用 staging 的 upstream-commit 回退 wine HEAD，
#       对 dwproton 这种独立分支是致命的）
#     - _versioning_string 走 Makefile.in 探测会自动落到 configure.ac，无需干预
#   source_ref 非空时：把 _plain_version 指向该 ref
#     （TkG 仅在 _use_staging != true 时才 checkout _plain_version，
#       正好与上面的强制关闭 staging 配合）
_WINE_SOURCE="$3"
_SOURCE_REF="$4"
if [ -n "$_WINE_SOURCE" ]; then
  echo "WINE SOURCE (custom): $_WINE_SOURCE"
  echo "SOURCE REF          : ${_SOURCE_REF:-(remote default)}"
  file_path2="$file_path/wine-tkg-profiles/advanced-customization.cfg"
  if [[ ! -f "$file_path2" ]]; then
    echo "File not found: $file_path2"
    exit 1
  fi
  sed -i "s|^_custom_wine_source=.*|_custom_wine_source=\"${_WINE_SOURCE}\"|" "$file_path2" || exit 1
  grep -q '^_custom_wine_source=' "$file_path2" || echo "_custom_wine_source=\"${_WINE_SOURCE}\"" >> "$file_path2"
  # 自定义源没有 staging 基线：强制关闭，否则 _prepare 会把 HEAD 回退到上游 commit
  file_path2="$file_path/customization.cfg"
  sed2 _use_staging false
  sed2 _staging_version ""
  if [ -n "$_SOURCE_REF" ]; then
    sed2 _plain_version "$_SOURCE_REF"
  fi
  echo "✅ _custom_wine_source 已写入，_use_staging=false"
fi

sed2 _wayland_driver false
sed2 _proton_battleye_support false
sed2 _proton_eac_support false
sed2 _mk11_fix false
sed2 _proton_fs_hack true
#10.16+不支持！！！
[[ $ENABLE_PROTON_MF == 1 ]] && ENABLE_PROTON_MF=true
[[ $ENABLE_PROTON_MF == true ]] && {
  if [[ $main_ver -lt 10 ]] || [[ $main_ver -eq 10 && $sub_ver -le 16 ]]; then
    sed2 _proton_winevulkan true
    sed2 _proton_mf_patches true
  else
    echo "Version > 10.16, setting _proton_winevulkan and _proton_mf_patches to false"
    sed2 _proton_winevulkan false
    sed2 _proton_mf_patches false
  fi
}
sed2 _msvcrt_nativebuiltin true
sed2 _win10_default true
sed2 _community_patches_auto_update true
sed2 _nomakepkg_prefix_path /tmp/output

if [ "$NO_STAGING" = "true" ]; then
  echo "NO_STAGING: 关闭 staging（对照构建：对齐纯净 wine）"
  sed2 _use_staging false
fi

file_path2="$file_path/wine-tkg-profiles/advanced-customization.cfg"
# -std=gnu17: GCC>=14 默认 C23，Wine 9.x 的 programs/winhlp32/macro.h 有成员叫 bool，会报
#            "two or more data types in declaration specifiers"
sed2 _GCC_FLAGS "-O3 -pipe -msse3 -mfpmath=sse -ftree-vectorize -std=gnu17 -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types"
sed2 _LD_FLAGS "-Wl,-O3,--sort-common,--as-needed"
sed2 _CROSS_FLAGS "-O3 -pipe -msse3 -mfpmath=sse -ftree-vectorize -std=gnu17 -Wno-error=implicit-function-declaration -Wno-error=incompatible-pointer-types"
sed2 _CROSS_LD_FLAGS "-Wl,-O3,--sort-common,--as-needed"
sed2 _NOLIB32 wow64
sed2 _configure_userargs64 "--disable-winemenubuilder --disable-win16 --disable-tests --without-capi --without-coreaudio --without-cups --without-gphoto --without-osmesa --without-oss --without-pcap --without-pcsclite --without-sane --without-udev --without-unwind --without-usb --without-v4l2 --without-wayland --without-xinerama --without-piper"
sed2 _user_patches_no_confirm true

echo "TkG Configuration file setting completed！"

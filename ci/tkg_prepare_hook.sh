
########################################################################
# Termux path fix + mfplat patch (auto-injected by CI)
########################################################################
_termux_path_fix() {
  local _src="${srcdir}/${_winesrcdir}"
  if [ ! -d "$_src" ]; then
    warning "Termux path fix: source dir not found: $_src"
    return 0
  fi
  msg2 "Applying Termux path fix in $_src"
  pushd "$_src" &>/dev/null

  find . -type f \( -name "*.c" -o -name "*.h" -o -name "*.in" -o -name "*.spec" \) \
    -exec grep -l "/tmp" {} \; | xargs -r sed -i 's|/tmp/|/data/data/com.termux/files/usr/tmp/|g'

  find server -type f \( -name "*.c" -o -name "*.h" \) \
    -exec sed -i 's|"/tmp"|"/data/data/com.termux/files/usr/tmp"|g' {} + 2>/dev/null || true

  find . -name "file.c" \
    -exec sed -i 's|"/tmp"|"/data/data/com.termux/files/usr/tmp"|g' {} + 2>/dev/null || true
  find . -name "loader.c" \
    -exec sed -i 's|"/tmp"|"/data/data/com.termux/files/usr/tmp"|g' {} + 2>/dev/null || true
  find . -name "server.c" \
    -exec sed -i 's|"/tmp"|"/data/data/com.termux/files/usr/tmp"|g' {} + 2>/dev/null || true

  # ---- mfplat DXGI device manager patch ----
  local _mfplat_patch_url="https://raw.githubusercontent.com/as14725836/wine-termux/main/wine_do_not_create_dxgi_device_manager2.patch"
  local _mfplat_patch_file="/tmp/wine-termux/wine_do_not_create_dxgi_device_manager2.patch"

  if [ -f "$_mfplat_patch_file" ]; then
    msg2 "Using existing mfplat patch: $_mfplat_patch_file"
  else
    msg2 "Downloading mfplat patch..."
    if wget -O "$_mfplat_patch_file" "$_mfplat_patch_url"; then
      msg2 "mfplat patch downloaded"
    else
      warning "mfplat patch download failed, skipping"
      _mfplat_patch_file=""
    fi
  fi

  if [ -n "$_mfplat_patch_file" ] && [ -f "$_mfplat_patch_file" ]; then
    if [ -f "dlls/mfplat/main.c" ]; then
      msg2 "Applying mfplat patch to dlls/mfplat/main.c"
      if patch -p1 --forward < "$_mfplat_patch_file"; then
        msg2 "mfplat patch applied successfully"
      else
        warning "mfplat patch failed or already applied, continuing"
      fi
    else
      warning "dlls/mfplat/main.c not found, skipping mfplat patch"
    fi
  fi
  # ---- mfplat patch end ----
  # ---- adapted-11.18 user patches ----
  for _up in 0060-quartz-implement-colour-filter.patch \
             0061-qasf-deliver-compressed-asf-streams.patch \
             termux-dns-fix.patch \
             wine-virtual-memory.patch \
             wine-virtual-memory-39bit-hiarea.patch \
             wine-box64-compat.patch \
             wine-box64-noexec.patch; do
    case "$_up" in
      wine-virtual-memory*)
        if [ -f /tmp/wine-termux/.skip39bit ]; then
          warning "SKIP39BIT: 跳过 userpatch $_up"
          continue
        fi
        ;;
    esac
    local _up_file="/tmp/wine-termux/$_up"
    local _up_url="https://raw.githubusercontent.com/as14725836/wine-termux/main/$_up"
    if [ ! -f "$_up_file" ]; then
      msg2 "Downloading userpatch $_up"
      if ! wget -O "$_up_file" "$_up_url"; then
        warning "userpatch download failed: $_up"
        continue
      fi
    fi
    msg2 "Applying userpatch $_up"
    if patch -p1 --forward --no-backup-if-mismatch < "$_up_file"; then
      msg2 "userpatch $_up applied OK"
    else
      warning "!!! userpatch $_up FAILED or already applied"
    fi
  done
  
  # ---- wine-virtual-memory.patch 校验 + 兜底（ARM64 39-bit VA 适配）----
  # 目标（补丁内容）：
  #   dlls/ntdll/unix/virtual.c : 三行 limit 0x7fffffff0000 -> 0x7fffff0000
  #   server/mapping.c          : free_map_addr(0x600000000000,0x100000000000) -> (0x4000000000,0x1000000000)
  #   loader/preloader.c        : `#ifdef __aarch64__` -> `#if 1`
  if [ -f /tmp/wine-termux/.skip39bit ]; then
    warning "SKIP39BIT: 跳过 wine-virtual-memory 适配（对照构建）"
  elif [ -f "dlls/ntdll/unix/virtual.c" ] && [ -f "server/mapping.c" ]; then
    VMC=$(grep -c '0x7fffff0000' dlls/ntdll/unix/virtual.c || true)
    if [ "${VMC}" = "0" ]; then
      warning "wine-virtual-memory 未生效 -> sed/perl 兜底"
      perl -pi -e 's/0x7fffffff0000/0x7fffff0000/ if /(address_space_limit|user_space_limit|working_set_limit)/' dlls/ntdll/unix/virtual.c
      sed -i 's/free_map_addr( 0x600000000000, 0x100000000000 )/free_map_addr( 0x4000000000, 0x1000000000 )/' server/mapping.c
      if [ -f loader/preloader.c ]; then
        perl -0pi -e 's/(preload_info\[i\]\.addr >= \(void \*\)0x10000\n)#ifdef __aarch64__/$1#if 1/' loader/preloader.c
      fi
    fi
    VMC=$(grep -c '0x7fffff0000' dlls/ntdll/unix/virtual.c || true)
    MPC=$(grep -c 'free_map_addr( 0x4000000000, 0x1000000000 )' server/mapping.c || true)
    PLC=$(grep -c '#if 1' loader/preloader.c 2>/dev/null || echo 0)
    msg2 "wine-virtual-memory check: virtual.c=${VMC} mapping.c=${MPC} preloader=${PLC}"
    if [ "${VMC}" = "0" ]; then
      echo "!!! FAIL: wine-virtual-memory 未生效（virtual.c 无 0x7fffff0000）"
      exit 1
    fi
  else
    warning "wine-virtual-memory: 找不到目标文件，跳过"
  fi
  # ---- wine-virtual-memory 结束 ----
# ---- 39-bit VA 完整化：Wine 的“高地址区”也必须落在 39-bit 以内 ----
# wine-virtual-memory.patch 只把三个 limit 降到 0x7fffff0000（512GB），
# 但 preloader 映射表与 virtual.c 的 no-preloader 兜底仍是 0x7ffffe000000（=128TB），
# 在 39-bit VA 设备上 mmap 必然失败 -> "install_bpf ... low addresses" + "map_fixed_area out of memory 0x7fff..."
if [ -f /tmp/wine-termux/.skip39bit ]; then
  warning "SKIP39BIT: 跳过高地址区适配（对照构建）"
elif [ -f loader/preloader.c ] && [ -f dlls/ntdll/unix/virtual.c ]; then
  _hi_files=$(grep -rl '0x7ffffe000000' --include='*.c' --include='*.h' . 2>/dev/null || true)
  for _f in $_hi_files; do
    msg2 "39-bit VA: 高区下移 0x7ffffe000000 -> 0x7ffe000000 in ${_f}"
    sed -i 's/0x7ffffe000000/0x7ffe000000/g' "$_f"
  done
  _old_files=$(grep -rl '0x7fffffff0000' --include='*.c' --include='*.h' . 2>/dev/null || true)
  for _f in $_old_files; do
    msg2 "39-bit VA: 旧上限残留 -> 0x7fffff0000 in ${_f}"
    sed -i 's/0x7fffffff0000/0x7fffff0000/g' "$_f"
  done
  HIA=$(grep -c '0x7ffe000000' loader/preloader.c || true)
  VMA=$(grep -c '0x7ffe000000' dlls/ntdll/unix/virtual.c || true)
  LEFT=$( { grep -rn '0x7ffffe000000\|0x7fffffff0000' --include='*.c' --include='*.h' . 2>/dev/null || true; } | wc -l )
  msg2 "39-bit VA check: preloader=${HIA} virtual=${VMA} leftover=${LEFT}"
  if [ "${HIA}" = "0" ] || [ "${VMA}" = "0" ] || [ "${LEFT}" != "0" ]; then
    echo "!!! FAIL: 39-bit VA 高区适配未生效 (preloader=${HIA} virtual=${VMA} leftover=${LEFT})"
    exit 1
  fi
else
  warning "39-bit VA: 找不到 preloader.c / virtual.c，跳过"
fi

  # ---- wine-box64-compat.patch 校验（box64/模拟器下的地址空间收敛）----
  if [ -f dlls/ntdll/unix/virtual.c ]; then
    EMD=$(grep -c 'wine_emulator_detected' dlls/ntdll/unix/virtual.c || true)
    EMF=$(grep -c 'wine_emulator_addr_space_limit' dlls/ntdll/unix/virtual.c || true)
    EMC=$(grep -c 'box64/emu compat' dlls/ntdll/unix/virtual.c || true)
    # noexec 放宽：老树靠 wine-box64-noexec.patch 注入 'noexec exec map relaxed' 文案；
    # wine-11.18+ 上游已自带等价逻辑（map_file_into_view 里 EACCES/EPERM + 只读映射
    # 直接 break 走 read() 兜底，另有 'noexec file system, falling back to read'），
    # 此时旧补丁本身就打不上（hunk 已不存在），两者任一命中即可放行。
    EMN1=$(grep -c 'noexec exec map relaxed' dlls/ntdll/unix/virtual.c || true)
    EMN2=$(grep -c 'falling back to read\|fall back to read()' dlls/ntdll/unix/virtual.c || true)
    EMN=$(( ${EMN1:-0} + ${EMN2:-0} ))
    msg2 "box64-compat check: detect=${EMD} limit_fn=${EMF} clamp=${EMC} noexec=${EMN} (patch=${EMN1} upstream=${EMN2})"
    if [ "${EMD}" = "0" ] || [ "${EMF}" = "0" ] || [ "${EMC}" = "0" ] || [ "${EMN}" = "0" ]; then
      echo "!!! FAIL: wine-box64-compat/noexec 未生效 (detect=${EMD} limit_fn=${EMF} clamp=${EMC} noexec=${EMN})"
      exit 1
    fi
  fi
  # ---- 39-bit VA：syscall-emulation（seccomp）阈值也在 39-bit 之外 ----
  # TkG/staging 的 install_bpf()（dlls/ntdll/unix/signal_*.c）用
  #   #define NATIVE_SYSCALL_ADDRESS_START 0x700000000000   (112 TB)
  #   test_syscall = mmap((void *)0x600000000000, ...)      (96 TB)
  # 来判断“原生库在高地址、PE 代码在低地址”。39-bit 设备上这两个值永远达不到，
  # 于是 seccomp 一辈子装不上，32 位 PE 代码的裸 syscall 就无人接管。
  # 这里把阈值降到 39-bit 空间内（64GB / 128GB），语义保持一致。
  if [ -f /tmp/wine-termux/.skip39bit ]; then
    warning "SKIP39BIT: 跳过 seccomp 阈值适配（对照构建）"
    _seccomp_files=""
  else
    _seccomp_files=$(grep -rl 'NATIVE_SYSCALL_ADDRESS_START' --include='*.c' . 2>/dev/null || true)
  fi
  for _f in $_seccomp_files; do
    msg2 "39-bit VA: seccomp 阈值下移 in ${_f}"
    perl -pi -e 's/(NATIVE_SYSCALL_ADDRESS_START\s+)0x[0-9a-fA-F]+/${1}0x1000000000/' "$_f"
    perl -pi -e 's/0x600000000000/0x2000000000/g if /test_syscall/' "$_f"
  done
  if [ -n "$_seccomp_files" ]; then
    _sc=$(cat $_seccomp_files 2>/dev/null | grep -cE 'NATIVE_SYSCALL_ADDRESS_START[[:space:]]+0x1000000000' || true)
    _old=$(cat $_seccomp_files 2>/dev/null | grep -cE 'NATIVE_SYSCALL_ADDRESS_START[[:space:]]+0x(700000000000|600000000000)' || true)
    msg2 "39-bit VA seccomp 明细:"; grep -nH 'NATIVE_SYSCALL_ADDRESS_START' $_seccomp_files 2>/dev/null | head -6 || true
    msg2 "39-bit VA seccomp check: new=${_sc} old=${_old}"
    if [ "${_sc}" = "0" ] || [ "${_old}" != "0" ]; then
      echo "!!! FAIL: seccomp 阈值未完成 39-bit 适配 (new=${_sc} old=${_old})"
      exit 1
    fi
  else
    warning "39-bit VA: 未找到 install_bpf 阈值（该树无 staging syscall-emulation），跳过"
  fi
  # ---- syscall-emulation 39-bit 结束 ----

  # --- .rej hard check ---
  if find . -name '*.rej' | head -5 | grep -q .; then
    warning "!!! .rej files detected:"
    find . -name '*.rej'
  fi
  
  # --- self check (visible in log) ---
  msg2 "self-check colour.c: $(ls dlls/quartz/colour.c 2>/dev/null || echo MISSING)"
  msg2 "self-check dns: $(grep -c init_dns_config dlls/ntdll/unix/loader.c 2>/dev/null || echo 0)"
  msg2 "self-check mfplat: $(grep -c resolver_create_default_handler dlls/mfplat/main.c 2>/dev/null || echo 0)"
  # ---- user patches end ----

  # ---- mfplat CLSID 兜底（wine-9.4 + TkG staging 混用）----
  # 现象（run #47 真实报错）：
  #   ../wine-git/dlls/mfplat/main.c:6299: error:
  #     'CLSID_MPEG4ByteStreamHandlerPlugin' undeclared
  # 原因：TkG staging 的 mfplat 改动用到了该 CLSID，但该版本的
  #       include/wine/mfinternal.idl 里没有这份 DEFINE_GUID 声明。
  # 处理：给 main.c 注入一个本地静态 GUID 并把引用改名（不依赖头文件，
  #       也不会和已有声明冲突）。
  if [ -f "dlls/mfplat/main.c" ] && grep -q '&CLSID_MPEG4ByteStreamHandlerPlugin' dlls/mfplat/main.c; then
    if grep -q '_wine_ci_mpeg4_bsh_clsid = {' dlls/mfplat/main.c; then
      msg2 "mfplat CLSID 兜底：已注入，跳过"
    else
      msg2 "mfplat CLSID 兜底：注入本地 GUID 定义"
      if grep -q '^#include "mfplat_private.h"$' dlls/mfplat/main.c; then
        sed -i 's|^#include "mfplat_private.h"$|#include "mfplat_private.h"\n\nstatic const GUID _wine_ci_mpeg4_bsh_clsid = {0x271c3902, 0x6095, 0x4c45, {0xa2, 0x2f, 0x20, 0x09, 0x18, 0x16, 0xee, 0x9e}};|' dlls/mfplat/main.c
      elif grep -q '^#include "initguid.h"$' dlls/mfplat/main.c; then
        sed -i 's|^#include "initguid.h"$|#include "initguid.h"\n\nstatic const GUID _wine_ci_mpeg4_bsh_clsid = {0x271c3902, 0x6095, 0x4c45, {0xa2, 0x2f, 0x20, 0x09, 0x18, 0x16, 0xee, 0x9e}};|' dlls/mfplat/main.c
      fi
      if grep -q '_wine_ci_mpeg4_bsh_clsid = {' dlls/mfplat/main.c; then
        sed -i 's|&CLSID_MPEG4ByteStreamHandlerPlugin|\&_wine_ci_mpeg4_bsh_clsid|g' dlls/mfplat/main.c
        msg2 "mfplat CLSID 兜底：引用已改名（$(grep -c '_wine_ci_mpeg4_bsh_clsid' dlls/mfplat/main.c) 处命中）"
      else
        warning "mfplat CLSID 兜底：未能插入定义，跳过改名（避免引入未定义符号）"
      fi
    fi
  else
    msg2 "mfplat CLSID 兜底：无需处理"
  fi
  # ---- mfplat CLSID 兜底 end ----

  popd &>/dev/null
  msg2 "Termux path fix done"
}
########################################################################

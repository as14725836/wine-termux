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

  # ---- 定点替换 Winlator 硬编码路径（这才是 10.10-custom 在非 __ANDROID__ 下的真问题）----
  # 实测（brunodev85/wine-10.10-custom @ main）：
  #   dlls/ntdll/unix/server.c:1288   init_server_dir() 的 #else 分支
  #   server/request.c:647            wineserver base_dir 的 #else 分支
  #   dlls/nsiproxy.sys/ndis.c:95     IFADDRS_PATH
  #   server/unicode.c:330            nls 目录搜索列表
  # 旧的 `s|/tmp/|termux|g` 会把 ".../files/rootfs/tmp/..." 变成
  #   ".../files/rootfs/data/data/com.termux/files/usr/tmp/..."（拼出垃圾路径），
  # 而 `"/tmp"` 那几条在 10.10 上 0 命中，所以这里改成按前缀定点替换。
  termux_tmp="/data/data/com.termux/files/usr/tmp"
  winlator_tmp="/data/data/com.winlator/files/rootfs/tmp"
  find . -type f \( -name "*.c" -o -name "*.h" \) \
    -exec grep -l "$winlator_tmp" {} \; | xargs -r sed -i "s|$winlator_tmp|$termux_tmp|g"

  for _pf in dlls/ntdll/unix/server.c server/request.c dlls/nsiproxy.sys/ndis.c; do
    msg2 "  $_pf -> $(grep -c "$termux_tmp" "$_pf" 2>/dev/null || echo 0) 处已改为 Termux 路径"
  done

  # nls 搜索列表：补上 Termux 的 wine 数据目录（该处本来就是多路径列表）
  sed -i "s|/data/data/com.winlator/files/rootfs/usr/local/share/wine/nls|/data/data/com.termux/files/usr/share/wine/nls|g" server/unicode.c 2>/dev/null || true

  # Z: 盘：这里被 Winlator 从上游的 "/" 改成了它的 rootfs，且**没有 #if 保护**，
  # 在 Termux 上该路径不存在 -> Z: 建不出来。恢复成上游行为（指向 /）。
  if grep -q 'symlink( "/data/data/com.winlator/files/rootfs", "dosdevices/z:" )' dlls/ntdll/unix/server.c; then
    sed -i 's|symlink( "/data/data/com.winlator/files/rootfs", "dosdevices/z:" )|symlink( "/", "dosdevices/z:" )|' dlls/ntdll/unix/server.c
    msg2 "  dosdevices/z: -> / （已恢复上游行为）"
  fi

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
      msg2 "Checking mfplat patch against dlls/mfplat/main.c"
      _out=$(patch -p1 --batch --dry-run --forward --no-backup-if-mismatch < "$_mfplat_patch_file" 2>&1) || true
      if echo "$_out" | grep -qE 'FAILED|hunk ignored|can.t find file'; then
        # 10.10 上实测：5 个 hunk 里有 1 个打不上。宁可整体跳过，也不要留半截补丁。
        warning "mfplat 补丁有 hunk 打不上，整体跳过："
        echo "$_out" | grep -E 'FAILED|hunk ignored' | head -5
      elif patch -p1 --batch --forward --no-backup-if-mismatch < "$_mfplat_patch_file"; then
        msg2 "mfplat patch applied successfully"
      else
        warning "mfplat patch failed, continuing"
      fi
    else
      warning "dlls/mfplat/main.c not found, skipping mfplat patch"
    fi
  fi
  # ---- mfplat patch end ----
  # ---- adapted-11.18 user patches ----
  for _up in 0060-quartz-implement-colour-filter.patch \
             0061-qasf-deliver-compressed-asf-streams.patch \
             termux-dns-fix.patch; do
    local _up_file="/tmp/wine-termux/$_up"
    local _up_url="https://raw.githubusercontent.com/as14725836/wine-termux/main/$_up"
    if [ ! -f "$_up_file" ]; then
      msg2 "Downloading userpatch $_up"
      if ! wget -O "$_up_file" "$_up_url"; then
        warning "userpatch download failed: $_up"
        continue
      fi
    fi
    msg2 "Checking userpatch $_up"
    _out=$(patch -p1 --batch --dry-run --forward --no-backup-if-mismatch < "$_up_file" 2>&1) || true
    if echo "$_out" | grep -qE 'FAILED|hunk ignored|can.t find file'; then
      warning "userpatch $_up 有 hunk 打不上，整体跳过："
      echo "$_out" | grep -E 'FAILED|hunk ignored' | head -5
    elif patch -p1 --batch --forward --no-backup-if-mismatch < "$_up_file"; then
      msg2 "userpatch $_up applied OK"
    else
      warning "!!! userpatch $_up FAILED"
    fi
  done
  
  # --- .rej hard check ---
  if find . -name '*.rej' | head -5 | grep -q .; then
    warning "!!! .rej files detected:"
    find . -name '*.rej'
  fi
  
  # --- self check (visible in log) ---
  msg2 "self-check colour.c: $(ls dlls/quartz/colour.c 2>/dev/null || echo MISSING)"
  msg2 "self-check dns: $(grep -c init_dns_config dlls/ntdll/unix/loader.c 2>/dev/null || echo 0)"
  msg2 "self-check mfplat: $(grep -c resolver_create_default_handler dlls/mfplat/main.c 2>/dev/null || echo 0)"
  msg2 "self-check termux tmp: server.c=$(grep -c 'com.termux/files/usr/tmp' dlls/ntdll/unix/server.c 2>/dev/null || echo 0) request.c=$(grep -c 'com.termux/files/usr/tmp' server/request.c 2>/dev/null || echo 0) ndis.c=$(grep -c 'com.termux/files/usr/tmp' dlls/nsiproxy.sys/ndis.c 2>/dev/null || echo 0)"
  msg2 "self-check 被跳过的补丁数: $(grep -c 'SKIPPED' "$_where"/prepare.log 2>/dev/null || echo 0)（详见 prepare.log）"
  # ---- user patches end ----

  popd &>/dev/null
  msg2 "Termux path fix done"
}
########################################################################

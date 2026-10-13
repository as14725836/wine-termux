# wincomponents

Windows 组件安装器（PyQt5，单文件）。界面和交互与 `dxvk` 版本选择器完全一致：
同一套深蓝渐变、流式卡片、拖拽缩放、单实例窗口、删除确认框。

**打开就列出组件，点一下卡片 = 自动下载并装进当前 wine。** 不需要准备任何别的文件。

## 装

```sh
pkg install python-pyqt5
./install.sh
wincomponents --selftest   # 先确认认对了环境
wincomponents               # 开界面
```

## 它做什么

点卡片：

1. 从 DroidDeck 的公开组件目录下载对应的 `*.tar.xz`
2. 解包，按 32/64 位分别放进 prefix 的
   `drive_c/windows/syswow64/`（32 位）和 `drive_c/windows/system32/`（64 位）
3. 写好 `WINEDLLOVERRIDES` 需要的那套 DLL overrides
4. 记下状态；再点「删除…」勾选卸载时，会把覆盖掉的原文件**原样还原**

## 环境怎么认的

和 `dxvk` 版本选择器走同一条路：

```
glibc/opt/conf/wine_path.conf  →  WINEPREFIX  →  当前 wine 目录
```

认到哪个 wine，组件就装进那个 prefix。界面顶部一直显示当前 wine + prefix。

每个 prefix 有一个稳定的 id（`prefix 路径的 sha1`），所以换 wine 之后
各 prefix 的组件选择互不干扰。

## 只列能一键装的

组件目录里有 123 个，本程序只列出**不需要 Windows 安装器**的那 63 个
（即只用解压 + 拷贝 DLL + 写 overrides 就能装好的）。

另外 60 个（`dotnet*`、`vcredist2013` 这种非 `_dll` 版、`K-Lite` …）需要在
Windows 里真的跑 `install_exe` / `install_msi`，界面里**不列**，状态行会提示
还有多少个被跳过。

## 缓存

- 组件目录：`~/.cache/wincomponents/components.json`（6 小时）
- 下载的包：`~/.cache/wincomponents/downloads/`
- 解包结果（store）：`~/.local/share/wincomponents/`
- 每个 prefix 的状态/备份：`~/.cache/wincomponents/<hash>/`

`--refresh` 强制重拉目录。

可用环境变量覆盖：`WC_STORE` `WC_CACHE` `WC_INSTALL_CACHE` `WC_SELECTION`。

## 卸载一个组件

点右下角「删除…」，勾选要撤掉的组件，确认。被这些组件覆盖过的 Wine 原文件
会从备份还原回原位。

## 安全

- 只往当前 prefix 的 `drive_c/windows/` 里写
- 覆盖前先把原文件备份进 `~/.cache/wincomponents/<hash>/.wc-apply-backup/`
- 组件名做白名单校验（`[A-Za-z0-9][A-Za-z0-9._-]{0,63}`）
- 下载走 HTTPS，带 md5 校验（目录里给的那份）

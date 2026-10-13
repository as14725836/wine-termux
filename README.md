# wincomponents GUI

> 源码：[`as14725836/wine-termux`](https://github.com/as14725836/wine-termux/blob/main/wincomponents)

给 Termux / Mobox 环境用的 **Windows 组件安装器**，界面和交互跟
[DXVK 版本选择器](dxvk) 完全一致（同一个 FlowLayout 流式卡片、同一套深蓝渐变
圆角窗口、同一套拖拽/缩放/删除对话框），只是把「DXVK 版本包」换成了
「Windows 组件」。

## 它干什么

点一个组件卡片 = 把这个组件装进**当前正在用的那个 Wine prefix**。

组件包括 VC++ 运行库、DirectX（d3dx9/d3dx11/d3dcompiler）、XInput、OpenAL、
XAudio、MSXML、quartz、gdiplus、mfc42、Windows 版本伪装等等。

## 环境是自动读的

和 DXVK 版本选择器读的是**同一个文件、同一个逻辑**：

```
wine_path.conf  →  export WINEPREFIX=...
                →  basename(dirname(prefix))  = 当前 wine 目录名
```

所以界面顶部显示的 `当前 wine: wine-10.0-3proton-vanilla-wow64` 就是你
模拟器此刻在用的那套 Wine，不需要手填。

`--selftest` 可以不开窗先确认它认对了：

```
wincomponents --selftest
```

## 安装

```sh
# 需要 PyQt5
pkg install python-pyqt5

./install.sh
```

## 组件从哪来

两个来源，同名时 store 优先：

1. **store** — `wc-install` 下载解包的组件（默认 `~/.local/share/wincomponents`，
   `WC_STORE` 可改）。带 DLL 覆盖设置和注册表写入。
2. **本地包** — `$PREFIX/wincomponents/*.tar.xz`，和 `$PREFIX/dxvk/*.tar.gz` 平行。

有 `wc-install` / `wc-apply` 时走完整的 store 流程（会写 `WINEDLLOVERRIDES`
和注册表）；没有时退回「直接把包解到 `drive_c/windows/`」——和 DXVK 版本选择器
一模一样的做法。

## 界面

- **搜索框** — 过滤组件
- **卡片区** — 点一下即装，装过的带 ✓
- **版本** — XP / Win7 / Win10，点了就改 prefix 的 `CurrentVersion`
- **一键** — 「常用库 / 老游戏 / DirectX」三组常用组合，一次装一批
- **删除…** — 勾选多个包一次性删掉（只删 `$PREFIX/wincomponents/` 里的）
- **取消** — 关窗

窗口可以拖拽移动、右下角缩放，和 DXVK 版一致。

## 安全

- 只写当前 prefix 的 `drive_c/windows/`（加 `WINEDLLOVERRIDES` / 注册表）
- 删除操作限定在 `$PREFIX/wincomponents/` 里，越界拒绝
- `wc-apply` 的状态文件和备份放在 `~/.cache/wincomponents/<hash>/`，
  不往用户 prefix 里塞东西
- 卸载（取消勾选后重新应用）会精确还原被替换的文件和注册表值

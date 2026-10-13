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







## 拖动 / 缩放窗口

窗口是无边框的（没有系统标题栏），所以**抓哪儿都能拖**：

- 卡片上按住拖动 → 拖窗口
- 状态行、进度条、按钮之间的空隙 → 拖窗口
- 窗口边缘 16px padding → 拖窗口
- **右下角 10px** → 拉伸缩放

不冲突的操作照常工作：**滚动条**能拖、**搜索框**能输入、
**卡片轻轻点一下**还是安装（位移小于 6px 算点击，超过才算拖动）。

### 为什么要自己处理鼠标

`QPushButton`（卡片就是）一旦按下就 **grab mouse**，之后的 `MouseMove`
全被它吃掉，窗口再也收不到 —— 结果就是"卡片上拖不动窗口"。

做法是按下时先 `return True` 拦住 grab，然后在 `MouseButtonRelease` 里
自己补一次 `click()`，否则卡片就点不动了：

```python
if event.type() == QEvent.MouseButtonPress and event.button() == Qt.LeftButton:
    ...
    self._press_obj = obj if isinstance(obj, QPushButton) else None
    if self._press_obj is not None:
        self._press_obj.setDown(True)
        return True          # 拦住 grab，MouseMove 才会发给我们

if event.type() == QEvent.MouseButtonRelease:
    if po is not None and not was_drag and po.isEnabled():
        if po.rect().contains(po.mapFromGlobal(event.globalPos())):
            po.click()       # 没拖动 -> 补一次点击
```

### 两个坑

1. **`frameGeometry` 判断缩放边要限定在窗口内** —— 滚动区里位置偏低的卡片，
   全局坐标的 `y` 可能超过窗口底边，会被误判成"抓右下角"，于是变成缩放而不是拖动。

2. **窗口自身也要装 eventFilter** —— `_install_drag_filter` 只遍历子控件，
   padding 空白处的按下事件得靠 `self.installEventFilter(self)` 才收得到。


## 没梯子也能下（多镜像自动回退）

`github.com` 的 releases 在国内直连基本是**龟速或直接超时**，所以下载不再只试直连，
而是**一组加速镜像里自动挑能用的那个**：

```
候选顺序（全新环境）：
  1. gh-proxy.com        实测最稳
  2. ghproxy.net
  3. ghfast.top
  4. gh.llkk.cc
  5. github.com          直连兜底
```

### 怎么选

**不预探测**（那会让首屏白等好几秒），而是**直接开下 + 热度窗口**：

- 连上后给 **8 秒**，这段时间下不满 **256 KB** 就判定"龟速"，立刻换下一个镜像
- 完全连不上的走 12 秒连接超时，然后换下一个
- **哪个下成功了就记住它**（写 `~/.cache/wincomponents/mirror.txt.<hash>`），
  之后同类文件优先用它，不再试错

实测（把直连完全封死的模拟环境）：

```
换取 gh-proxy.com 成功（跳过了 github.com:timeout）
下好 18.7 MB  耗时 13.9s
记住的镜像: https://gh-proxy.com/
```

### 相关命令 / 变量

```sh
wincomponents --mirror-test        # 实测每个镜像能不能用、多快
```

```
WC_MIRROR=https://你的反代/   # 强制走某个前缀（自建反代、公司代理）
```

> 目录文件（`raw.githubusercontent.com`）单独一组镜像 —— 路径形态和 releases 不同，
> 有些代理只支持其中一种。


## 安装进度条

装东西的时候，状态行**正下方**会出现一条进度条（横贯整个宽度），
平时是藏起来的。

```
可安装 63 个组件（在线）　·　wine: xxx
▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░  下载 d3dx9.tar.xz  58
[搜索框]
[卡片网格]
```

进度分两段：

| 阶段 | 范围 | 说明 |
|---|---|---|
| 下载 | 0 ~ 80% | 按 `Content-Length` 算真实字节进度 |
| 解包 / 应用 | 80 ~ 100% | 没字节进度，匀速爬升到 95%，结束直接 100% |

装完（或失败）后停满格 0.6 秒再收起。

**一键装多个组件**时按组件数平分进度，并显示第几个：

```
▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░  2/4 d3dx11  42
```

### 实现要点

- 引擎侧的 `download()` 加了 `progress(done, total, filename)` 回调，
  逐层传到 `install_one(..., progress=)`
- 后台线程**不能直接改控件** —— 走 `pyqtSignal` 排队到 UI 线程：

```python
class _Progress(QObject):
    changed = pyqtSignal(int, str)      # (百分比, 说明文字)
```

- Qt 的 `setFormat()` 只认 `%p` / `%v` / `%m`，**不认 `%s`** ——
  文案要直接拼进 format 字符串：`setFormat("下载 x  %p")`


## 悬停提示（半透明浮层）

鼠标/长按停在卡片或状态行上会弹一个**半透明**的提示：能透出底下的界面，
不是一块实心黑方块。四角也是真透明（圆角处不会露黑边）。

```
┌─────────────────────────────┐
│ d3dx9                       │   ← 圆角，透出背景
│ Microsoft d3dx9 DLLs from   │
│ DirectX 9 redistributable   │
│ 大小 18.7 MB                │
│ 装这些：d3dx9_24, d3dx9_25, │
│ d3dx9_26, d3dx9_27 等 20 个 │
│ 点一下安装                  │
└─────────────────────────────┘
```


### 内建 tooltip 是彻底关掉的

自绘浮层只是"额外加了一个"，如果某个控件还留着 `setToolTip(...)`，
Qt 会**同时**弹它自己的黑方块 —— 而且往往比自绘浮层先出现。

所以这里做了两层：

1. 所有控件一律 `setToolTip("")`（含卡片、状态行、按钮、删除对话框的复选框）
2. `QApplication` 上装一个全局过滤器，把所有 `QEvent.ToolTip` 直接吃掉：

```python
class _NoToolTipFilter(QObject):
    def eventFilter(self, obj, event):
        if event.type() == QEvent.ToolTip:
            QToolTip.hideText()
            return True          # 不让 Qt 自己弹
        return False
```

自绘的 `HoverTip` 走 `enterEvent` / `eventFilter`，不依赖 `ToolTip` 事件，不受影响。

### 为什么不用内建的 QToolTip

Qt 会先把 `QToolTip` 画到一张**不透明位图**上，stylesheet 里写
`background-color: rgba(...)` 也会被拍平成实色 —— 在深色界面上就是一块
黑方块。而且 `QToolTip` 是独立顶层窗口，把样式挂在 dialog 上对它无效。

所以这里自己实现了一个 `HoverTip`：

```python
class HoverTip(QWidget):
    setAttribute(Qt.WA_TranslucentBackground, True)   # ← 真半透明
    setWindowFlags(Qt.ToolTip | Qt.FramelessWindowHint)
    def paintEvent(...):  # 自绘圆角矩形，背景 alpha≈208
```

- 背景 `rgba(24,34,56,208)`，描边 `rgba(120,190,235,160)`
- 卡片悬停走 `enterEvent`/`leaveEvent`
- 按钮和状态行走 `eventFilter`（`_attach_hover_tip`）
- 自动定位：优先摆在控件下方，放不下就翻到上方，再不行贴边夹回
- 长路径按 `/` 折行、长文本按空格/逗号折行，不会被拉成一根横条

## 顶栏

状态行只写 `wine: <名字>`，不会显示一长串 `/data/data/...` 路径。

鼠标/长按悬停在状态行上才会弹出完整信息：

```
wine    : wine-10.0-3proton-vanilla-wow64
prefix  : /data/data/com.termux/.../.wine
wine 根 : /data/data/com.termux/.../wine-10.0-3proton-vanilla-wow64
安装到  : .../drive_c/windows/
版本    : win10
```

## 卡片

一张卡片 = 一个组件，自动排成整齐的网格（左对齐、行列间距一致、窗口变宽列数变多）。

```
┌──────────────────────┐
│ xinput            ✓  │   ← 组件名 + 已装标记
│ xinput1_1 · xinput1_2 · xinput1_3  …+1 │   ← 这个组件会装哪些 DLL
│ 120.4 KB             │   ← 下载大小
└──────────────────────┘
```

- **DLL 列表**从组件目录的 `override_dll` 步骤里提（最准），没有就退回 `copy_dll` 的文件名
- 装超过 3 个只显示前 3 个 + `…+N`，鼠标悬停能看到完整列表
- 装好的卡片描边变绿并显示 **✓**；再点一下 = 重装
- 点一下装完后只刷新那一张卡片（列表不重建，滚动位置不丢）

卡片的按钮宽度会按窗口宽度自动撑满（132–260 pt 之间），保证每行右边不留半截。

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

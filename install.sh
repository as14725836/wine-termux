#!/data/data/com.termux/files/usr/bin/bash
# 把 wincomponents GUI 装进 Termux（设备端运行这个，不要在 PC 上跑）
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$PREFIX/bin/wincomponents"
SHARE="$PREFIX/share/wincomponents"

echo "==> 安装 wincomponents GUI"
echo "    源:   $SRC"
echo "    目标: $DEST"

# PyQt5 检查
if ! python3 -c "import PyQt5" 2>/dev/null; then
    echo "!! 没有 PyQt5。先装："
    echo "     pkg install python-pyqt5"
    echo "   （glibc 环境里的话用 pip 装：pip install PyQt5）"
    exit 1
fi

mkdir -p "$SHARE"
install -m 755 "$SRC/wincomponents" "$DEST"
install -m 644 "$SRC/README.md" "$SHARE/README.md" 2>/dev/null || true

# 组件包目录
mkdir -p "$PREFIX/wincomponents"

echo "==> 完成。"
echo
echo "  用法："
echo "    wincomponents            打开界面"
echo "    wincomponents --selftest 只看环境，不开窗"
echo
echo "  组件包放 $PREFIX/wincomponents/*.tar.xz"
echo "  或者用 wc-install 下到 store 里，界面会自动列出来"

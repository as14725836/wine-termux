#!/data/data/com.termux/files/usr/bin/bash
# 把 wincomponents 装进 Termux（在设备上跑，别在 PC 上跑）
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
DEST="$PREFIX/bin/wincomponents"

echo "==> 安装 wincomponents"
echo "    源:   $SRC/wincomponents"
echo "    目标: $DEST"

if ! python3 -c "import PyQt5" 2>/dev/null; then
    echo "!! 没有 PyQt5，先装："
    echo "     pkg install python-pyqt5"
    echo "   （glibc 环境里： pip install PyQt5）"
    exit 1
fi

install -m 755 "$SRC/wincomponents" "$DEST"

echo "==> 完成"
echo
echo "  wincomponents            打开界面（点组件卡片即下载+安装）"
echo "  wincomponents --selftest 只看环境，不开窗"
echo "  wincomponents --refresh  强制重拉组件目录"
echo
echo "  组件装进当前 wine 的 prefix（读 wine_path.conf 认，和 dxvk 选择器一致）。"

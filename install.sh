#!/bin/bash
# SogouGlass 一键安装：从源码编译 App，装到 ~/Applications 并启动。
# 首次启动时 App 会自动安装透明皮肤并让搜狗切换过去。
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/SogouGlass.app"
BUILD="build/SogouGlass.app"

red()   { printf "\033[31m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }

# 1. 环境检查
major=$(sw_vers -productVersion | cut -d. -f1)
if [ "$major" -lt 26 ]; then
  red "需要 macOS 26 或更高版本（液态玻璃是 macOS 26 才有的），当前是 $(sw_vers -productVersion)。"
  exit 1
fi
if [ ! -d "/Library/Input Methods/SogouInput.app" ]; then
  red "没有找到搜狗输入法，请先安装搜狗输入法 Mac 版：https://pinyin.sogou.com/mac/"
  exit 1
fi
if ! xcrun --find swiftc >/dev/null 2>&1; then
  red "需要 Xcode 命令行工具来编译。请先运行下面的命令安装，装好后再运行本脚本："
  echo "  xcode-select --install"
  exit 1
fi

# 2. 编译并打包
echo "正在编译 SogouGlass ..."
rm -rf "$BUILD"
mkdir -p "$BUILD/Contents/MacOS" "$BUILD/Contents/Resources"
xcrun swiftc -O -target "$(uname -m)-apple-macos26.0" -o "$BUILD/Contents/MacOS/SogouGlass" Sources/*.swift
cp Resources/Info.plist "$BUILD/Contents/Info.plist"
cp -R Skin/LiquidGlass "$BUILD/Contents/Resources/LiquidGlass"
codesign --force --deep --sign - "$BUILD" >/dev/null 2>&1

# 3. 替换旧版本并启动
pkill -f "SogouGlass.app/Contents/MacOS/SogouGlass" 2>/dev/null || true
sleep 0.5
mkdir -p "$HOME/Applications"
rm -rf "$APP"
cp -R "$BUILD" "$APP"
open "$APP"

green "安装完成！菜单栏会出现一个水滴图标，打几个字试试吧。"
echo "想开机自动启动：点菜单栏水滴图标 → 开机自动启动。"
echo "卸载：运行 ./uninstall.sh"

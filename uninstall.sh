#!/bin/bash
# SogouGlass 卸载：还原搜狗默认皮肤、移除液态玻璃皮肤、取消开机自启、删除 App 和设置。
set -uo pipefail

APP="$HOME/Applications/SogouGlass.app"

pkill -f "SogouGlass.app/Contents/MacOS/SogouGlass" 2>/dev/null
sleep 0.5
if [ -x "$APP/Contents/MacOS/SogouGlass" ]; then
  "$APP/Contents/MacOS/SogouGlass" --uninstall
fi
rm -rf "$APP"
defaults delete com.zijue.sogouglass >/dev/null 2>&1

echo "已卸载，搜狗输入法已恢复默认皮肤。"

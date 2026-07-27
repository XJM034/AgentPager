#!/bin/zsh
set -euo pipefail

项目根目录="${0:A:h:h}"
输出目录="$项目根目录/dist"
应用目录="$输出目录/AgentPager Bridge.app"
DMG路径="$输出目录/AgentPager-macOS.dmg"
暂存目录="$(mktemp -d)"

清理暂存目录() {
    rm -R "$暂存目录"
}
trap 清理暂存目录 EXIT

"$项目根目录/scripts/package-macos.sh"

mkdir -p "$输出目录"
cp -R "$应用目录" "$暂存目录/AgentPager Bridge.app"
ln -s /Applications "$暂存目录/Applications"

hdiutil create \
    -volname "AgentPager" \
    -srcfolder "$暂存目录" \
    -ov \
    -format UDZO \
    "$DMG路径"

echo "$DMG路径"

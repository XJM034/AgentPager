#!/bin/zsh
set -euo pipefail

项目根目录="${0:A:h:h}"
应用目录="$项目根目录/dist/AgentGrid Bridge.app"
内容目录="$应用目录/Contents"
可执行目录="$内容目录/MacOS"

cd "$项目根目录/macos"
swift build -c release

mkdir -p "$可执行目录"
cp "$项目根目录/macos/.build/release/AgentGridBridge" "$可执行目录/AgentGridBridge"
cp "$项目根目录/macos/.build/release/AgentGridHooks" "$可执行目录/AgentGridHooks"
cp "$项目根目录/macos/AppInfo.plist" "$内容目录/Info.plist"
chmod +x "$可执行目录/AgentGridBridge" "$可执行目录/AgentGridHooks"

签名身份="${AGENTGRID_CODESIGN_IDENTITY:-}"
if [[ -z "$签名身份" ]]; then
    签名身份="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1)"
fi

if [[ -n "$签名身份" ]]; then
    # 使用稳定的开发者身份，避免每次打包后因临时签名变化而触发钥匙串授权。
    codesign --force --deep --options runtime --sign "$签名身份" "$应用目录"
    echo "已使用稳定签名：$签名身份"
else
    # 没有开发者证书的机器仍可本地构建，但首次启动可能需要确认钥匙串访问。
    codesign --force --deep --sign - "$应用目录"
    echo "未找到 Apple Development 证书，已使用临时签名"
fi
echo "$应用目录"

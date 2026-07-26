#!/bin/zsh
set -euo pipefail

项目根目录="${0:A:h:h}"
应用目录="$项目根目录/dist/AgentGrid Bridge.app"
内容目录="$应用目录/Contents"
可执行目录="$内容目录/MacOS"
资源目录="$内容目录/Resources"
应用可执行文件="$可执行目录/AgentGridBridge"
需要恢复运行=0

# 覆盖正在执行的签名代码会被 macOS 判定为签名失效，先正常结束同一路径实例。
for 进程号 in ${(f)"$(pgrep -x AgentGridBridge 2>/dev/null || true)"}; do
    [[ -n "$进程号" ]] || continue
    进程命令="$(ps -p "$进程号" -o command= 2>/dev/null || true)"
    if [[ "$进程命令" == "$应用可执行文件" ]]; then
        需要恢复运行=1
        kill "$进程号"
        for _ in {1..50}; do
            kill -0 "$进程号" 2>/dev/null || break
            sleep 0.1
        done
        if kill -0 "$进程号" 2>/dev/null; then
            echo "AgentGrid Bridge 未能在 5 秒内退出，已停止打包以保护运行中的应用" >&2
            exit 1
        fi
    fi
done

cd "$项目根目录/macos"
swift build -c release

mkdir -p "$可执行目录" "$资源目录"
cp "$项目根目录/macos/.build/release/AgentGridBridge" "$可执行目录/AgentGridBridge"
cp "$项目根目录/macos/.build/release/AgentGridHooks" "$可执行目录/AgentGridHooks"
cp "$项目根目录/macos/AppInfo.plist" "$内容目录/Info.plist"
cp "$项目根目录/assets/fonts/fusion_pixel_12px_zh_hans.ttf" \
    "$资源目录/fusion_pixel_12px_zh_hans.ttf"
cp "$项目根目录/docs/FUSION-PIXEL-OFL.txt" "$资源目录/FUSION-PIXEL-OFL.txt"
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

if (( 需要恢复运行 )); then
    open -n "$应用目录"
    echo "已恢复运行 AgentGrid Bridge"
fi
echo "$应用目录"

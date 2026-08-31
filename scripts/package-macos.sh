#!/bin/zsh
set -euo pipefail

项目根目录="${0:A:h:h}"
应用目录="$项目根目录/dist/AgentPager Bridge.app"
内容目录="$应用目录/Contents"
可执行目录="$内容目录/MacOS"
资源目录="$内容目录/Resources"
应用可执行文件="$可执行目录/AgentPagerBridge"
需要恢复运行=0

# 覆盖正在执行的签名代码会被 macOS 判定为签名失效，先正常结束同一路径实例。
for 进程号 in ${(f)"$(pgrep -x AgentPagerBridge 2>/dev/null || true)"}; do
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
            echo "AgentPager Bridge 未能在 5 秒内退出，已停止打包以保护运行中的应用" >&2
            exit 1
        fi
    fi
done

cd "$项目根目录/macos"

if [[ "${AGENTPAGER_UNIVERSAL:-0}" == "1" ]]; then
    ARM缓存目录="$项目根目录/macos/.build/agentpager-arm64"
    X86缓存目录="$项目根目录/macos/.build/agentpager-x86_64"
    ARM构建目录="$(swift build -c release \
        --scratch-path "$ARM缓存目录" \
        --triple arm64-apple-macosx14.0 --show-bin-path)"
    X86构建目录="$(swift build -c release \
        --scratch-path "$X86缓存目录" \
        --triple x86_64-apple-macosx14.0 --show-bin-path)"
    swift build -c release \
        --scratch-path "$ARM缓存目录" \
        --triple arm64-apple-macosx14.0
    swift build -c release \
        --scratch-path "$X86缓存目录" \
        --triple x86_64-apple-macosx14.0

    mkdir -p "$可执行目录" "$资源目录"
    lipo -create \
        "$ARM构建目录/AgentGridBridge" \
        "$X86构建目录/AgentGridBridge" \
        -output "$可执行目录/AgentPagerBridge"
    lipo -create \
        "$ARM构建目录/AgentGridHooks" \
        "$X86构建目录/AgentGridHooks" \
        -output "$可执行目录/AgentPagerHooks"
else
    构建目录="$(swift build -c release --show-bin-path)"
    swift build -c release
    mkdir -p "$可执行目录" "$资源目录"
    cp "$构建目录/AgentGridBridge" "$可执行目录/AgentPagerBridge"
    cp "$构建目录/AgentGridHooks" "$可执行目录/AgentPagerHooks"
fi

cp "$项目根目录/macos/AppInfo.plist" "$内容目录/Info.plist"
cp "$项目根目录/assets/brand/AgentPager.icns" "$资源目录/AgentPager.icns"
cp "$项目根目录/assets/fonts/fusion_pixel_12px_zh_hans.ttf" \
    "$资源目录/fusion_pixel_12px_zh_hans.ttf"
cp "$项目根目录/LICENSES/FUSION-PIXEL-NOTICE.txt" \
    "$资源目录/FUSION-PIXEL-NOTICE.txt"
cp "$项目根目录/LICENSES/OFL-1.1.txt" "$资源目录/OFL-1.1.txt"
cp "$项目根目录/LICENSE" "$资源目录/GPL-3.0.txt"
cp "$项目根目录/NOTICE.md" "$资源目录/NOTICE.md"
chmod +x "$可执行目录/AgentPagerBridge" "$可执行目录/AgentPagerHooks"

if [[ -n "${AGENTPAGER_VERSION_NAME:-}" ]]; then
    /usr/libexec/PlistBuddy -c \
        "Set :CFBundleShortVersionString $AGENTPAGER_VERSION_NAME" \
        "$内容目录/Info.plist"
fi
if [[ -n "${AGENTPAGER_VERSION_CODE:-}" ]]; then
    /usr/libexec/PlistBuddy -c \
        "Set :CFBundleVersion $AGENTPAGER_VERSION_CODE" \
        "$内容目录/Info.plist"
fi

签名身份="${AGENTPAGER_CODESIGN_IDENTITY:-${AGENTGRID_CODESIGN_IDENTITY:-}}"
本地签名标识文件="$HOME/Library/Application Support/AgentPager/signing-identity.sha1"
if [[ -z "$签名身份" && -f "$本地签名标识文件" ]]; then
    签名身份="$(tr -d '[:space:]' < "$本地签名标识文件")"
    if [[ ! "$签名身份" =~ '^[[:xdigit:]]{40}$' ]]; then
        echo "AgentPager 本地签名标识格式无效，已停止打包；不会静默降级为临时签名" >&2
        exit 1
    fi
fi
if [[ -z "$签名身份" ]]; then
    签名身份="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
        | head -n 1)"
fi

if [[ -n "$签名身份" ]]; then
    # 使用稳定的开发者身份，避免每次打包后因临时签名变化而触发钥匙串授权。
    codesign --force --deep --options runtime --sign "$签名身份" "$应用目录"
    if [[ "$签名身份" == "-" ]]; then
        echo "已显式使用临时签名；更新后可能需要重新授权钥匙串"
    else
        echo "已使用证书签名：$签名身份（后续更新需沿用同一身份）"
    fi
else
    # 没有开发者证书的机器仍可本地构建，但首次启动可能需要确认钥匙串访问。
    codesign --force --deep --sign - "$应用目录"
    echo "未找到 Apple Development 证书，已使用临时签名；更新后可能需要重新授权钥匙串"
fi

if (( 需要恢复运行 )); then
    open -n "$应用目录"
    echo "已恢复运行 AgentPager Bridge"
fi
echo "$应用目录"

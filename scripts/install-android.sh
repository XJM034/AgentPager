#!/bin/zsh
set -euo pipefail

项目根目录="${0:A:h:h}"
安卓目录="$项目根目录/android"
APK路径="$安卓目录/app/build/outputs/apk/debug/app-debug.apk"
# 与 android/app/build.gradle.kts 中 debug 的 applicationIdSuffix ".custom" 保持同步。
自定义包名="com.agentgrid.mobile.custom"
启动页面="com.agentgrid.mobile.MainActivity"

JDK目录="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
if [[ ! -x "$JDK目录/bin/java" ]]; then
  print -u2 -- "未找到 JDK 17；请先运行 scripts/android-doctor.sh"
  exit 1
fi

if ! command -v android >/dev/null 2>&1 || ! command -v adb >/dev/null 2>&1; then
  print -u2 -- "未找到 android CLI 或 adb；请先运行 scripts/android-doctor.sh"
  exit 1
fi

设备序列号="${ANDROID_SERIAL:-}"
if [[ -z "$设备序列号" ]]; then
  设备列表=()
  while IFS= read -r 当前设备; do
    [[ -n "$当前设备" ]] && 设备列表+=("$当前设备")
  done < <(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
  if (( ${#设备列表[@]} == 0 )); then
    print -u2 -- "没有已连接的 Android 设备。请连接 Redmi，或先运行：android emulator start medium_phone"
    exit 1
  fi
  if (( ${#设备列表[@]} > 1 )); then
    print -u2 -- "检测到多个设备，请先设置 ANDROID_SERIAL 后重试："
    adb devices -l >&2
    exit 1
  fi
  设备序列号="$设备列表[1]"
fi

cd "$安卓目录"
JAVA_HOME="$JDK目录" ./gradlew testDebugUnitTest assembleDebug
android run \
  --device="$设备序列号" \
  --apks="$APK路径" \
  --activity="$启动页面"

进程已启动=false
for _ in {1..20}; do
  if adb -s "$设备序列号" shell pidof "$自定义包名" >/dev/null; then
    进程已启动=true
    break
  fi
  sleep 0.5
done

if [[ "$进程已启动" != true ]]; then
  print -u2 -- "APK 已部署，但未检测到 $自定义包名 正在运行"
  exit 1
fi

print -- "已在 $设备序列号 启动 AgentPager Custom（$自定义包名）"

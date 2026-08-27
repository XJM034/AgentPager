#!/bin/zsh
set -euo pipefail

项目根目录="${0:A:h:h}"
安卓目录="$项目根目录/android"
本地属性="$安卓目录/local.properties"

if [[ ! -f "$本地属性" ]]; then
  print -u2 -- "缺少 android/local.properties，无法确定 Android SDK 路径"
  exit 1
fi

SDK目录="$(sed -n 's/^sdk.dir=//p' "$本地属性" | tail -n 1)"
if [[ -z "$SDK目录" || ! -d "$SDK目录" ]]; then
  print -u2 -- "android/local.properties 中的 sdk.dir 无效：$SDK目录"
  exit 1
fi

JDK目录="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
if [[ ! -x "$JDK目录/bin/java" ]]; then
  print -u2 -- "未找到 Homebrew OpenJDK 17：$JDK目录"
  exit 1
fi

for 必需命令 in android adb; do
  if ! command -v "$必需命令" >/dev/null 2>&1; then
    print -u2 -- "缺少必需命令：$必需命令"
    exit 1
  fi
done

if [[ ! -d "/Applications/Android Studio.app" ]]; then
  print -u2 -- "未安装 Android Studio"
  exit 1
fi

print -- "Android Studio：$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' '/Applications/Android Studio.app/Contents/Info.plist')"
print -- "Android CLI：$(android -V)"
print -- "Android SDK：$SDK目录"
print -- "JDK：$(JAVA_HOME="$JDK目录" "$JDK目录/bin/java" -version 2>&1 | head -n 1)"
print -- "Gradle：$(JAVA_HOME="$JDK目录" "$安卓目录/gradlew" --version | awk '/^Gradle / { print $2; exit }')"
虚拟设备列表="$(android emulator list)"
print -- "已定义虚拟设备："
if [[ -n "${虚拟设备列表//[[:space:]]/}" ]]; then
  print -- "$虚拟设备列表" | sed 's/^/  - /'
else
  print -- "  - 暂无（模拟器系统镜像尚未成功下载）"
fi
print -- "当前 adb 设备："
adb devices -l | sed 's/^/  /'

if [[ -z "${虚拟设备列表//[[:space:]]/}" ]]; then
  print -u2 -- "基础开发工具检查通过；模拟器仍待配置"
  exit 2
fi

print -- "Android 开发环境检查通过（含模拟器）"

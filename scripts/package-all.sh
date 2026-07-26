#!/bin/zsh
set -euo pipefail

项目根目录="${0:A:h:h}"
安卓目录="$项目根目录/android"
JDK目录="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
输出目录="$项目根目录/dist"

"$项目根目录/scripts/package-macos.sh"

cd "$安卓目录"
JAVA_HOME="$JDK目录" ./gradlew testDebugUnitTest assembleDebug

mkdir -p "$输出目录"
cp "$安卓目录/app/build/outputs/apk/debug/app-debug.apk" \
    "$输出目录/AgentGrid-debug.apk"

echo "$输出目录"

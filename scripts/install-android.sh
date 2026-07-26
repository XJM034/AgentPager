#!/bin/zsh
set -euo pipefail

项目根目录="${0:A:h:h}"
安卓目录="$项目根目录/android"
JDK目录="/Applications/Android Studio.app/Contents/jbr/Contents/Home"

cd "$安卓目录"
JAVA_HOME="$JDK目录" ./gradlew testDebugUnitTest assembleDebug
adb install -r "$安卓目录/app/build/outputs/apk/debug/app-debug.apk"
adb shell am start -n com.agentgrid.mobile/.MainActivity


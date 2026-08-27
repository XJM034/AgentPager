# Android 子项目说明

本目录是 AgentPager 原生 Android App，使用 Kotlin、Jetpack Compose 和 Gradle Wrapper。当前定制目标是个人 Debug 版，与原作者正式版并存。

## 构建事实

- 模块：`:app`
- JDK/JVM：17
- compileSdk / targetSdk：36
- minSdk：29（Android 10）
- UI：Jetpack Compose
- Debug 包名：`com.agentgrid.mobile.custom`
- Debug 名称：`AgentPager Custom`
- SDK 路径来自未提交的 `android/local.properties`

版本和依赖以 `app/build.gradle.kts`、`gradle/libs.versions.toml` 和 Gradle Wrapper 为准，不从聊天或旧构建产物猜测。

## 修改边界

- 亮度策略：`app/src/main/java/com/agentgrid/mobile/ScreenBrightnessPolicy.kt`
- 设置状态与持久化：`app/src/main/java/com/agentgrid/mobile/AgentGridViewModel.kt`
- 窗口亮度应用：`app/src/main/java/com/agentgrid/mobile/MainActivity.kt`
- Compose 界面：`app/src/main/java/com/agentgrid/mobile/ui/AgentGridScreen.kt`
- 对应逻辑测试：`app/src/test/`

保留 `.custom` 包名后缀、定制名称和独立数据空间。除非用户明确要求发布，不要增加 release 签名配置或复用原作者签名。

## 开发与验证

从仓库根目录先运行：

```bash
scripts/android-doctor.sh
```

逻辑或 UI 修改至少运行：

```bash
cd android
JAVA_HOME="/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home" \
  ./gradlew testDebugUnitTest lintDebug assembleDebug
```

验证顺序：

1. 可独立渲染的 Compose UI 添加或更新 `@Preview`。
2. 在 `medium_phone` 模拟器安装并启动，读取布局、截图和日志。
3. 亮度、常亮、相机、振动、通知、开机启动、后台限制和 MIUI 行为使用 Redmi 真机复验。

安装目标必须明确。多个设备同时在线时设置 `ANDROID_SERIAL`，再运行 `scripts/install-android.sh`。

## 运行边界

- App 通过局域网明文 WebSocket 连接本机 AgentPager Bridge；这是现有本地产品边界，不等于允许互联网明文通信。
- 配对凭据保存在 Android 本地安全存储中，不得输出到文档、日志摘要或 Git。
- 模拟器可验证 UI、配对和大部分业务流程，但不能证明真实屏幕亮度或 MIUI 策略。
- 当前只有 JVM 单元测试，没有 `androidTest` 仪器测试；不要把单元测试描述成完整设备集成测试。

更多命令和服务状态见 [../docs/android-development.md](../docs/android-development.md)。

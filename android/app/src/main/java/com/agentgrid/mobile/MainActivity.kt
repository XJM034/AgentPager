package com.agentgrid.mobile

import android.os.Bundle
import android.util.Base64
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.agentgrid.mobile.ui.AgentGridScreen

class MainActivity : ComponentActivity() {
    private val viewModel: AgentGridViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.attributes = window.attributes.apply {
            screenBrightness = ScreenBrightnessPolicy.brightnessFor(
                lifecycle = viewModel.state.value.focusedTask?.lifecycle,
                activeBrightness = viewModel.state.value.activeTaskBrightness,
                idleBrightness = viewModel.state.value.idleBrightness,
            )
        }
        enterTerminalMode()
        importPairing(intent)

        setContent {
            val state by viewModel.state.collectAsStateWithLifecycle()
            LaunchedEffect(
                state.focusedTask?.lifecycle,
                state.activeTaskBrightness,
                state.idleBrightness,
            ) {
                window.attributes = window.attributes.apply {
                    screenBrightness = ScreenBrightnessPolicy.brightnessFor(
                        lifecycle = state.focusedTask?.lifecycle,
                        activeBrightness = state.activeTaskBrightness,
                        idleBrightness = state.idleBrightness,
                    )
                }
            }
            AgentGridScreen(
                state = state,
                onPair = viewModel::pair,
                onUnpair = viewModel::unpair,
                onControl = viewModel::control,
                onFocus = viewModel::focus,
                onToggleDashboard = viewModel::toggleDashboard,
                onActiveTaskBrightnessChange = viewModel::setActiveTaskBrightness,
                onIdleBrightnessChange = viewModel::setIdleBrightness,
                onExitTerminal = {
                    viewModel.setTerminalMode(false)
                    exitTerminalMode()
                },
            )
        }
    }

    override fun onStart() {
        super.onStart()
        // 从桌面或最近任务返回时也恢复全屏，不沿用上一次临时退出状态。
        viewModel.setTerminalMode(true)
        enterTerminalMode()
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // singleTask 在已有窗口上再次打开时可能不会重新调用 onStart。
        viewModel.setTerminalMode(true)
        enterTerminalMode()
        importPairing(intent)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && viewModel.state.value.terminalMode) {
            enterTerminalMode()
        }
    }

    private fun enterTerminalMode() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    private fun exitTerminalMode() {
        WindowCompat.setDecorFitsSystemWindows(window, true)
        WindowInsetsControllerCompat(window, window.decorView)
            .show(WindowInsetsCompat.Type.systemBars())
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    private fun importPairing(intent: android.content.Intent) {
        intent.getStringExtra(EXTRA_PAIRING)?.let(viewModel::pair)
        intent.getStringExtra(EXTRA_PAIRING_BASE64)?.let { encoded ->
            runCatching {
                Base64.decode(encoded, Base64.DEFAULT).decodeToString()
            }.getOrNull()?.let(viewModel::pair)
        }
    }

    companion object {
        const val EXTRA_PAIRING = "pairing"
        const val EXTRA_PAIRING_BASE64 = "pairingBase64"
    }
}

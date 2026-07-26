package com.agentgrid.mobile.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.agentgrid.mobile.AgentGridUiState
import com.agentgrid.mobile.SoundEngine
import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.ControlAction
import com.agentgrid.mobile.domain.PendingRequest
import com.agentgrid.mobile.domain.PendingRequestKind
import com.agentgrid.mobile.domain.TaskCapability
import com.agentgrid.mobile.domain.TaskSnapshot
import com.agentgrid.mobile.domain.UsageWindow
import com.agentgrid.mobile.network.LinkState
import com.agentgrid.mobile.render.PixelCoreSurfaceView
import com.agentgrid.mobile.render.PixelRenderState
import kotlinx.coroutines.delay

@Composable
fun AgentGridScreen(
    state: AgentGridUiState,
    onPair: (String) -> Unit,
    onUnpair: () -> Unit,
    onControl: (String, ControlAction, String?) -> Unit,
    onFocus: (String) -> Unit,
    onExitTerminal: () -> Unit,
) {
    AgentGridTheme {
        if (state.pairing == null) {
            PairingScreen(state, onPair)
        } else {
            TaskTerminal(
                state = state,
                onUnpair = onUnpair,
                onControl = onControl,
                onFocus = onFocus,
                onExitTerminal = onExitTerminal,
            )
        }
    }
}

@Composable
private fun PairingScreen(
    state: AgentGridUiState,
    onPair: (String) -> Unit,
) {
    var manualText by remember { mutableStateOf("") }
    Row(
        modifier = Modifier
            .fillMaxSize()
            .background(AgentGridColors.Background)
            .padding(28.dp),
        horizontalArrangement = Arrangement.spacedBy(28.dp),
    ) {
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight()
                .background(AgentGridColors.Surface),
        ) {
            QRCodeScanner(onResult = onPair, modifier = Modifier.fillMaxSize())
        }
        Column(
            modifier = Modifier
                .weight(0.92f)
                .fillMaxHeight(),
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                "AGENTGRID",
                color = AgentGridColors.Text,
                fontSize = 30.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 2.sp,
            )
            Spacer(Modifier.height(10.dp))
            Text("扫描 Mac 端配对码", color = AgentGridColors.Cyan, fontSize = 16.sp)
            Spacer(Modifier.height(22.dp))
            OutlinedTextField(
                value = manualText,
                onValueChange = { manualText = it },
                label = { Text("或粘贴配对文本") },
                minLines = 3,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(10.dp))
            Button(
                onClick = { onPair(manualText) },
                enabled = manualText.isNotBlank(),
                shape = RectangleShape,
            ) {
                Text("连接 Bridge")
            }
            state.pairingError?.let {
                Spacer(Modifier.height(10.dp))
                Text(it, color = AgentGridColors.Red, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun TaskTerminal(
    state: AgentGridUiState,
    onUnpair: () -> Unit,
    onControl: (String, ControlAction, String?) -> Unit,
    onFocus: (String) -> Unit,
    onExitTerminal: () -> Unit,
) {
    val tasks = remember(state.tasks) {
        state.tasks.sortedWith(
            compareByDescending<TaskSnapshot> { it.attentionPriority }
                .thenByDescending { it.updatedAt },
        )
    }
    val urgentTask = tasks.firstOrNull {
        it.lifecycle == AgentLifecycle.WAITING_APPROVAL ||
            it.lifecycle == AgentLifecycle.WAITING_ANSWER ||
            it.lifecycle == AgentLifecycle.FAILED
    }
    var expandedTaskID by remember { mutableStateOf<String?>(null) }
    var settingsVisible by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val sound = remember(context) { SoundEngine(context) }

    LaunchedEffect(urgentTask?.id, urgentTask?.lifecycle) {
        if (urgentTask != null) {
            expandedTaskID = urgentTask.id
        }
    }
    LaunchedEffect(tasks.map { it.id to it.lifecycle }) {
        tasks.maxByOrNull { it.attentionPriority }?.let {
            if (!it.isMuted) sound.play(it.lifecycle)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AgentGridColors.Background),
    ) {
        TopControls(
            windows = state.usage?.windows.orEmpty(),
            settingsVisible = settingsVisible,
            onToggleSettings = { settingsVisible = !settingsVisible },
            modifier = Modifier.align(Alignment.TopEnd),
        )

        if (tasks.isEmpty()) {
            EmptyState(
                connected = state.linkState == LinkState.CONNECTED,
                modifier = Modifier.align(Alignment.Center),
            )
        } else {
            Column(
                modifier = Modifier
                    .align(Alignment.Center)
                    .fillMaxWidth()
                    .padding(horizontal = 20.dp)
                    .heightIn(max = 306.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(0.dp),
            ) {
                tasks.take(5).forEach { task ->
                    val pending = state.pendingRequests.firstOrNull { it.taskID == task.id }
                    TaskRow(
                        task = task,
                        pending = pending,
                        expanded = expandedTaskID == task.id,
                        dimmed = urgentTask != null && urgentTask.id != task.id,
                        onClick = {
                            val willExpand = expandedTaskID != task.id
                            expandedTaskID = if (willExpand) task.id else null
                            onFocus(task.id)
                        },
                        onControl = onControl,
                    )
                }
            }
        }

        AnimatedVisibility(
            visible = settingsVisible,
            enter = fadeIn(tween(140)),
            exit = fadeOut(tween(110)),
            modifier = Modifier
                .align(Alignment.TopEnd)
                .padding(top = 54.dp, end = 18.dp),
        ) {
            SettingsPanel(
                state = state,
                onUnpair = onUnpair,
                onExitTerminal = onExitTerminal,
            )
        }

        if (state.linkState != LinkState.CONNECTED) {
            Text(
                "BRIDGE OFFLINE · 正在重连",
                color = AgentGridColors.Dimmed,
                fontSize = 10.sp,
                letterSpacing = 1.sp,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 10.dp),
            )
        }
    }
}

@Composable
private fun TopControls(
    windows: List<UsageWindow>,
    settingsVisible: Boolean,
    onToggleSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier.padding(top = 14.dp, end = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        windows.take(2).forEach { window ->
            UsagePill(window)
        }
        Text(
            if (settingsVisible) "×" else "SET",
            color = if (settingsVisible) AgentGridColors.Amber else AgentGridColors.Muted,
            fontSize = 13.sp,
            fontWeight = FontWeight.Bold,
            modifier = Modifier
                .background(AgentGridColors.Surface)
                .clickable(onClick = onToggleSettings)
                .padding(horizontal = 10.dp, vertical = 7.dp)
                .semantics { contentDescription = "打开设置" },
        )
    }
}

@Composable
private fun UsagePill(window: UsageWindow) {
    val color = when {
        window.remainingPercentage < 10 -> AgentGridColors.Red
        window.remainingPercentage < 20 -> AgentGridColors.Orange
        else -> AgentGridColors.Cyan
    }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(
            "${window.label} ${window.remainingPercentage.toInt()}%",
            color = AgentGridColors.Muted,
            fontSize = 9.sp,
        )
        LinearProgressIndicator(
            progress = { (window.remainingPercentage / 100).toFloat() },
            modifier = Modifier
                .width(74.dp)
                .height(3.dp),
            color = color,
            trackColor = AgentGridColors.Divider,
            gapSize = 0.dp,
            drawStopIndicator = {},
        )
    }
}

@Composable
private fun TaskRow(
    task: TaskSnapshot,
    pending: PendingRequest?,
    expanded: Boolean,
    dimmed: Boolean,
    onClick: () -> Unit,
    onControl: (String, ControlAction, String?) -> Unit,
) {
    val rowAlpha by animateFloatAsState(
        targetValue = if (dimmed) 0.34f else 1f,
        animationSpec = tween(180),
        label = "任务行注意力",
    )
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(if (expanded) AgentGridColors.Surface else Color.Transparent)
            .clickable(onClick = onClick)
            .animateContentSize(
                animationSpec = spring(dampingRatio = 0.86f, stiffness = 420f),
            )
            .padding(horizontal = 4.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(78.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            AndroidView(
                factory = { PixelCoreSurfaceView(it) },
                update = {
                    it.updateState(
                        PixelRenderState(
                            lifecycle = task.lifecycle,
                            activity = task.activity,
                        ),
                    )
                    it.alpha = rowAlpha
                },
                modifier = Modifier
                    .size(70.dp)
                    .semantics { contentDescription = "任务状态 ${statusText(task.lifecycle)}" },
            )

            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 8.dp, end = 14.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    task.title,
                    color = AgentGridColors.Text.copy(alpha = rowAlpha),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    task.userPrompt?.let { "你：$it" } ?: "你：—",
                    color = AgentGridColors.Muted.copy(alpha = rowAlpha),
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    task.latestStep ?: statusText(task.lifecycle),
                    color = statusColor(task).copy(alpha = rowAlpha),
                    fontSize = 10.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }

            TaskMeta(task = task, alpha = rowAlpha)
        }

        AnimatedVisibility(
            visible = expanded,
            enter = expandVertically(tween(210)) + fadeIn(tween(180)),
            exit = shrinkVertically(tween(170)) + fadeOut(tween(120)),
        ) {
            TaskDetails(
                task = task,
                pending = pending,
                onControl = onControl,
            )
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .height(1.dp)
                .background(AgentGridColors.Divider.copy(alpha = if (expanded) 0f else 0.7f)),
        )
    }
}

@Composable
private fun TaskMeta(task: TaskSnapshot, alpha: Float) {
    val elapsed by produceState(0L, task.id, task.lifecycle) {
        while (true) {
            value = (System.currentTimeMillis() - task.startedAt).coerceAtLeast(0)
            delay(1_000)
        }
    }
    Column(
        modifier = Modifier.widthIn(min = 166.dp, max = 210.dp),
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            MetaTag("Codex", AgentGridColors.Blue, alpha)
            MetaTag(
                if (task.source.name == "CODEX_DESKTOP") "ChatGPT.app" else "Terminal",
                AgentGridColors.Muted,
                alpha,
            )
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                formatTokens(task.tokenUsage?.total),
                color = AgentGridColors.Muted.copy(alpha = alpha),
                fontSize = 9.sp,
            )
            Text(
                formatElapsed(elapsed),
                color = AgentGridColors.Muted.copy(alpha = alpha),
                fontSize = 9.sp,
            )
            Box(
                modifier = Modifier
                    .size(7.dp)
                    .background(statusColor(task).copy(alpha = alpha)),
            )
        }
    }
}

@Composable
private fun MetaTag(text: String, color: Color, alpha: Float) {
    Text(
        text,
        color = color.copy(alpha = alpha),
        fontSize = 9.sp,
        modifier = Modifier
            .background(AgentGridColors.SurfaceRaised.copy(alpha = alpha))
            .padding(horizontal = 7.dp, vertical = 4.dp),
    )
}

@Composable
private fun TaskDetails(
    task: TaskSnapshot,
    pending: PendingRequest?,
    onControl: (String, ControlAction, String?) -> Unit,
) {
    var answer by remember(task.id) { mutableStateOf("") }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 150.dp)
            .verticalScroll(rememberScrollState())
            .padding(start = 82.dp, end = 18.dp, bottom = 14.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        task.userPrompt?.let {
            DetailLine("INPUT", it, AgentGridColors.Text)
        }
        task.latestStep?.let {
            DetailLine("STEP", it, statusColor(task))
        }
        task.tokenUsage?.let {
            DetailLine(
                "TOKEN",
                "IN ${formatTokens(it.input)} · CACHE ${formatTokens(it.cachedInput)} · OUT ${formatTokens(it.output)} · TOTAL ${formatTokens(it.total)}",
                AgentGridColors.Cyan,
            )
        }
        pending?.summary?.let {
            DetailLine(
                if (pending.kind == PendingRequestKind.APPROVAL) "APPROVAL" else "QUESTION",
                it,
                if (pending.kind == PendingRequestKind.APPROVAL) AgentGridColors.Amber else AgentGridColors.Yellow,
            )
        }

        if (
            pending?.kind == PendingRequestKind.APPROVAL &&
            TaskCapability.APPROVE in task.capabilities
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                PixelButton("允许", AgentGridColors.Green) {
                    onControl(task.id, ControlAction.APPROVE, null)
                }
                PixelButton("拒绝", AgentGridColors.Red) {
                    onControl(task.id, ControlAction.DENY, null)
                }
            }
        } else if (
            pending?.kind == PendingRequestKind.QUESTION &&
            TaskCapability.ANSWER in task.capabilities
        ) {
            OutlinedTextField(
                value = answer,
                onValueChange = { answer = it },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 3,
            )
            PixelButton("发送回答", AgentGridColors.Yellow) {
                if (answer.isNotBlank()) {
                    onControl(task.id, ControlAction.ANSWER, answer)
                }
            }
        }

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            PixelButton(if (task.isPinned) "取消固定" else "固定", AgentGridColors.Violet) {
                onControl(task.id, ControlAction.PIN, null)
            }
            PixelButton(if (task.isMuted) "恢复声音" else "静音", AgentGridColors.Muted) {
                onControl(task.id, ControlAction.MUTE, null)
            }
            if (task.isUnread) {
                PixelButton("标为已读", AgentGridColors.Cyan) {
                    onControl(task.id, ControlAction.MARK_READ, null)
                }
            }
        }
    }
}

@Composable
private fun DetailLine(label: String, value: String, color: Color) {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(label, color = color, fontSize = 9.sp, modifier = Modifier.width(58.dp))
        Text(value, color = AgentGridColors.Muted, fontSize = 10.sp)
    }
}

@Composable
private fun PixelButton(
    label: String,
    color: Color,
    action: () -> Unit,
) {
    OutlinedButton(
        onClick = action,
        shape = RectangleShape,
        colors = ButtonDefaults.outlinedButtonColors(contentColor = color),
        contentPadding = ButtonDefaults.TextButtonContentPadding,
    ) {
        Text(label, fontSize = 10.sp)
    }
}

@Composable
private fun SettingsPanel(
    state: AgentGridUiState,
    onUnpair: () -> Unit,
    onExitTerminal: () -> Unit,
) {
    Column(
        modifier = Modifier
            .width(206.dp)
            .background(AgentGridColors.Surface)
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("设置", color = AgentGridColors.Text, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        DetailLine(
            "LINK",
            if (state.linkState == LinkState.CONNECTED) "已连接" else "正在重连",
            if (state.linkState == LinkState.CONNECTED) AgentGridColors.Green else AgentGridColors.Red,
        )
        DetailLine("TASK", "${state.tasks.size}", AgentGridColors.Cyan)
        PixelButton("解除配对", AgentGridColors.Red, onUnpair)
        PixelButton("退出专用模式", AgentGridColors.Muted, onExitTerminal)
    }
}

@Composable
private fun EmptyState(
    connected: Boolean,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        AndroidView(
            factory = { PixelCoreSurfaceView(it) },
            update = {
                it.updateState(
                    PixelRenderState(
                        lifecycle = if (connected) AgentLifecycle.IDLE else AgentLifecycle.OFFLINE,
                    ),
                )
            },
            modifier = Modifier.size(76.dp),
        )
        Text(
            if (connected) "等待 Codex 任务" else "等待 Bridge",
            color = AgentGridColors.Muted,
            fontSize = 11.sp,
        )
    }
}

private fun statusText(lifecycle: AgentLifecycle): String = when (lifecycle) {
    AgentLifecycle.OFFLINE -> "离线"
    AgentLifecycle.IDLE -> "空闲"
    AgentLifecycle.STARTING -> "正在启动"
    AgentLifecycle.RUNNING -> "正在运行"
    AgentLifecycle.WAITING_APPROVAL -> "等待批准"
    AgentLifecycle.WAITING_ANSWER -> "等待回答"
    AgentLifecycle.SUCCEEDED -> "任务完成"
    AgentLifecycle.FAILED -> "任务失败"
    AgentLifecycle.INTERRUPTED -> "已中断"
}

private fun statusColor(task: TaskSnapshot): Color = when (task.lifecycle) {
    AgentLifecycle.WAITING_APPROVAL -> AgentGridColors.Amber
    AgentLifecycle.WAITING_ANSWER -> AgentGridColors.Yellow
    AgentLifecycle.SUCCEEDED -> AgentGridColors.Green
    AgentLifecycle.FAILED -> AgentGridColors.Red
    AgentLifecycle.INTERRUPTED, AgentLifecycle.OFFLINE -> AgentGridColors.Muted
    AgentLifecycle.IDLE -> AgentGridColors.Cyan
    AgentLifecycle.STARTING -> AgentGridColors.Violet
    AgentLifecycle.RUNNING -> when (task.activity?.name) {
        "READING", "SEARCHING", "BROWSING" -> AgentGridColors.Cyan
        "EDITING" -> AgentGridColors.Indigo
        "EXECUTING" -> AgentGridColors.Orange
        "TESTING" -> AgentGridColors.Blue
        else -> AgentGridColors.Violet
    }
}

private fun formatElapsed(milliseconds: Long): String {
    val totalSeconds = milliseconds / 1_000
    val hours = totalSeconds / 3_600
    val minutes = totalSeconds % 3_600 / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        "%d:%02d:%02d".format(hours, minutes, seconds)
    } else {
        "%02d:%02d".format(minutes, seconds)
    }
}

private fun formatTokens(value: Int?): String {
    val tokens = value ?: return "— tok"
    return when {
        tokens >= 1_000_000 -> "%.1fm tok".format(tokens / 1_000_000.0)
        tokens >= 1_000 -> "%.1fk tok".format(tokens / 1_000.0)
        else -> "$tokens tok"
    }
}

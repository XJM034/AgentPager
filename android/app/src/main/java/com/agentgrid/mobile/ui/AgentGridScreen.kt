package com.agentgrid.mobile.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
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
            TerminalScreen(
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
            .padding(32.dp),
        horizontalArrangement = Arrangement.spacedBy(32.dp),
    ) {
        Box(
            Modifier
                .weight(1f)
                .fillMaxHeight()
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(4.dp))
                .background(AgentGridColors.Surface),
        ) {
            QRCodeScanner(
                onResult = onPair,
                modifier = Modifier.fillMaxSize(),
            )
            PixelCorners(Modifier.fillMaxSize())
        }

        Column(
            modifier = Modifier
                .weight(0.86f)
                .fillMaxHeight(),
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                "AGENTGRID",
                color = AgentGridColors.Text,
                fontWeight = FontWeight.Black,
                fontSize = 34.sp,
                letterSpacing = 3.sp,
                fontFamily = PixelFontFamily,
            )
            Spacer(Modifier.height(12.dp))
            Text(
                "扫描 Mac 上 AgentGrid Bridge 的二维码。",
                color = AgentGridColors.Muted,
                fontSize = 17.sp,
            )
            Spacer(Modifier.height(30.dp))
            OutlinedTextField(
                value = manualText,
                onValueChange = { manualText = it },
                label = { Text("或粘贴配对文本") },
                minLines = 4,
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(Modifier.height(12.dp))
            Button(
                onClick = { onPair(manualText) },
                enabled = manualText.isNotBlank(),
            ) {
                Text("连接 Bridge")
            }
            state.pairingError?.let {
                Spacer(Modifier.height(12.dp))
                Text(it, color = AgentGridColors.Red)
            }
        }
    }
}

@Composable
private fun TerminalScreen(
    state: AgentGridUiState,
    onUnpair: () -> Unit,
    onControl: (String, ControlAction, String?) -> Unit,
    onFocus: (String) -> Unit,
    onExitTerminal: () -> Unit,
) {
    val focused = state.focusedTask
    val pendingRequest = state.pendingRequests.firstOrNull { it.taskID == focused?.id }
    val context = LocalContext.current
    val sound = remember(context) { SoundEngine(context) }
    var detailsVisible by remember { mutableStateOf(false) }
    var cornerTaps by remember { mutableIntStateOf(0) }
    var horizontalDrag by remember { mutableStateOf(0f) }

    LaunchedEffect(focused?.id, focused?.lifecycle) {
        focused?.lifecycle?.let(sound::play)
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(AgentGridColors.Background)
            .pointerInput(state.tasks, focused?.id) {
                detectHorizontalDragGestures(
                    onHorizontalDrag = { _, amount -> horizontalDrag += amount },
                    onDragEnd = {
                        val currentIndex = state.tasks.indexOfFirst { it.id == focused?.id }
                        val target = when {
                            horizontalDrag < -80 && currentIndex < state.tasks.lastIndex -> currentIndex + 1
                            horizontalDrag > 80 && currentIndex > 0 -> currentIndex - 1
                            else -> currentIndex
                        }
                        state.tasks.getOrNull(target)?.let { onFocus(it.id) }
                        horizontalDrag = 0f
                    },
                )
            },
    ) {
        AndroidView(
            factory = { context -> PixelCoreSurfaceView(context) },
            update = { view ->
                view.updateState(
                    PixelRenderState(
                        lifecycle = focused?.lifecycle
                            ?: if (state.linkState == LinkState.CONNECTED) AgentLifecycle.IDLE else AgentLifecycle.OFFLINE,
                        activity = focused?.activity,
                    ),
                )
            },
            modifier = Modifier
                .fillMaxSize()
                .combinedClickable(
                    onClick = { detailsVisible = !detailsVisible },
                    onDoubleClick = {
                        focused?.let { onControl(it.id, ControlAction.MUTE, null) }
                    },
                    onLongClick = {
                        focused?.let { onControl(it.id, ControlAction.PIN, null) }
                    },
                )
                .semantics {
                    contentDescription = "当前任务像素状态核心"
                },
        )

        Header(
            linkState = state.linkState,
            onCornerTap = {
                cornerTaps += 1
                if (cornerTaps >= 5) {
                    cornerTaps = 0
                    onExitTerminal()
                }
            },
            modifier = Modifier.align(Alignment.TopStart),
        )

        UsageBars(
            windows = state.usage?.windows.orEmpty(),
            modifier = Modifier.align(Alignment.TopEnd),
        )

        TaskLabel(
            task = focused,
            detailsVisible = detailsVisible,
            modifier = Modifier.align(Alignment.CenterStart),
        )

        TaskStrip(
            tasks = state.tasks,
            focusedID = focused?.id,
            onFocus = onFocus,
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 18.dp),
        )

        if (focused?.lifecycle == AgentLifecycle.WAITING_APPROVAL) {
            ApprovalPanel(
                task = focused,
                summary = pendingRequest?.summary,
                onControl = onControl,
                modifier = Modifier.align(Alignment.BottomEnd),
            )
        }

        if (focused?.lifecycle == AgentLifecycle.WAITING_ANSWER) {
            AnswerPanel(
                task = focused,
                prompt = pendingRequest?.summary,
                onControl = onControl,
                modifier = Modifier.align(Alignment.BottomEnd),
            )
        }

        if (detailsVisible) {
            OutlinedButton(
                onClick = onUnpair,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 18.dp),
            ) {
                Text("解除配对")
            }
        }
    }
}

@Composable
private fun Header(
    linkState: LinkState,
    onCornerTap: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .combinedClickable(onClick = onCornerTap)
            .padding(24.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Box(
            Modifier
                .size(9.dp)
                .background(
                    if (linkState == LinkState.CONNECTED) AgentGridColors.Green else AgentGridColors.Orange,
                ),
        )
        Column {
            Text(
                "AGENTGRID",
                color = AgentGridColors.Text,
                fontWeight = FontWeight.Black,
                letterSpacing = 2.sp,
                fontFamily = PixelFontFamily,
            )
            Text(
                when (linkState) {
                    LinkState.CONNECTED -> "BRIDGE ONLINE"
                    LinkState.CONNECTING -> "CONNECTING"
                    LinkState.DISCONNECTED -> "BRIDGE OFFLINE"
                },
                color = AgentGridColors.Muted,
                fontSize = 10.sp,
                letterSpacing = 1.sp,
                fontFamily = PixelFontFamily,
            )
        }
    }
}

@Composable
private fun UsageBars(
    windows: List<UsageWindow>,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier.padding(24.dp),
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        windows.take(2).forEach { window ->
            val color = when {
                window.remainingPercentage < 10 -> AgentGridColors.Red
                window.remainingPercentage < 20 -> AgentGridColors.Orange
                else -> AgentGridColors.Cyan
            }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(9.dp),
            ) {
                Text(
                    "${window.label} ${window.remainingPercentage.toInt()}%",
                    color = AgentGridColors.Muted,
                    fontSize = 11.sp,
                )
                LinearProgressIndicator(
                    progress = { (window.remainingPercentage / 100.0).toFloat() },
                    modifier = Modifier
                        .width(104.dp)
                        .height(6.dp),
                    color = color,
                    trackColor = AgentGridColors.SurfaceRaised,
                    gapSize = 0.dp,
                    drawStopIndicator = {},
                )
            }
        }
    }
}

@Composable
private fun TaskLabel(
    task: TaskSnapshot?,
    detailsVisible: Boolean,
    modifier: Modifier = Modifier,
) {
    val elapsed by produceState(initialValue = 0L, task?.id) {
        while (true) {
            value = task?.let { (System.currentTimeMillis() - it.startedAt).coerceAtLeast(0) } ?: 0
            delay(1_000)
        }
    }

    Column(
        modifier.padding(start = 28.dp),
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Text(
            task?.projectName ?: "等待任务",
            color = AgentGridColors.Text,
            fontWeight = FontWeight.Bold,
            fontSize = 22.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            statusText(task?.lifecycle),
            color = statusColor(task?.lifecycle),
            fontSize = 13.sp,
            letterSpacing = 1.sp,
        )
        if (task != null) {
            Text(
                formatElapsed(elapsed),
                color = AgentGridColors.Muted,
                fontSize = 12.sp,
            )
        }
        if (detailsVisible && task?.activity != null) {
            Text(
                "当前活动：${task.activity.name.lowercase()}",
                color = AgentGridColors.Muted,
                fontSize = 12.sp,
            )
        }
    }
}

@Composable
private fun TaskStrip(
    tasks: List<TaskSnapshot>,
    focusedID: String?,
    onFocus: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    LazyRow(
        modifier = modifier.fillMaxWidth(0.58f),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        items(tasks, key = { it.id }) { task ->
            Button(
                onClick = { onFocus(task.id) },
                colors = ButtonDefaults.buttonColors(
                    containerColor = if (task.id == focusedID) {
                        AgentGridColors.SurfaceRaised
                    } else {
                        Color.Transparent
                    },
                ),
                contentPadding = ButtonDefaults.TextButtonContentPadding,
            ) {
                MiniPixelCore(task.lifecycle)
                Spacer(Modifier.width(7.dp))
                Text(
                    task.projectName,
                    color = if (task.id == focusedID) AgentGridColors.Text else AgentGridColors.Muted,
                    fontSize = 11.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun MiniPixelCore(lifecycle: AgentLifecycle) {
    val color = statusColor(lifecycle)
    Canvas(Modifier.size(18.dp)) {
        val cell = size.width / 3f
        repeat(3) { row ->
            repeat(3) { column ->
                if ((row + column) % 2 == 0 || row == 1) {
                    drawRect(
                        color = color,
                        topLeft = Offset(column * cell + 1, row * cell + 1),
                        size = androidx.compose.ui.geometry.Size(cell - 2, cell - 2),
                    )
                }
            }
        }
    }
}

@Composable
private fun ApprovalPanel(
    task: TaskSnapshot,
    summary: String?,
    onControl: (String, ControlAction, String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier
            .padding(end = 28.dp, bottom = 88.dp)
            .width(280.dp)
            .background(AgentGridColors.Surface)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text("需要你的批准", fontWeight = FontWeight.Bold, fontSize = 18.sp)
        Text(
            summary ?: "原始操作只在请求有效期间显示，不会保存。",
            color = AgentGridColors.Muted,
            fontSize = 12.sp,
        )
        if (
            TaskCapability.APPROVE in task.capabilities &&
            TaskCapability.DENY in task.capabilities
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Button(
                    onClick = { onControl(task.id, ControlAction.APPROVE, null) },
                    colors = ButtonDefaults.buttonColors(containerColor = AgentGridColors.Green),
                ) { Text("允许", color = AgentGridColors.Background) }
                OutlinedButton(
                    onClick = { onControl(task.id, ControlAction.DENY, null) },
                ) { Text("拒绝", color = AgentGridColors.Red) }
            }
        } else {
            Text("请回到 Mac 处理这次批准", color = AgentGridColors.Amber)
        }
    }
}

@Composable
private fun AnswerPanel(
    task: TaskSnapshot,
    prompt: String?,
    onControl: (String, ControlAction, String?) -> Unit,
    modifier: Modifier = Modifier,
) {
    var answer by remember(task.id) { mutableStateOf("") }
    Column(
        modifier = modifier
            .padding(end = 28.dp, bottom = 88.dp)
            .width(320.dp)
            .background(AgentGridColors.Surface)
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("Codex 正在等待回答", fontWeight = FontWeight.Bold)
        prompt?.let {
            Text(it, color = AgentGridColors.Muted, fontSize = 12.sp)
        }
        if (TaskCapability.ANSWER in task.capabilities) {
            OutlinedTextField(
                value = answer,
                onValueChange = { answer = it },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 3,
            )
            Button(
                onClick = { onControl(task.id, ControlAction.ANSWER, answer) },
                enabled = answer.isNotBlank(),
            ) { Text("发送回答") }
        } else {
            Text(
                "当前 Codex 通道只提供等待提示，请回到 Mac 回答。",
                color = AgentGridColors.Amber,
                fontSize = 12.sp,
            )
        }
    }
}

@Composable
private fun PixelCorners(modifier: Modifier = Modifier) {
    Canvas(modifier) {
        val color = AgentGridColors.Amber
        val length = 26.dp.toPx()
        val inset = 12.dp.toPx()
        val thickness = 3.dp.toPx()
        drawRect(color, Offset(inset, inset), androidx.compose.ui.geometry.Size(length, thickness))
        drawRect(color, Offset(inset, inset), androidx.compose.ui.geometry.Size(thickness, length))
        drawRect(color, Offset(size.width - inset - length, size.height - inset - thickness), androidx.compose.ui.geometry.Size(length, thickness))
        drawRect(color, Offset(size.width - inset - thickness, size.height - inset - length), androidx.compose.ui.geometry.Size(thickness, length))
    }
}

private fun statusText(lifecycle: AgentLifecycle?): String = when (lifecycle) {
    AgentLifecycle.STARTING -> "正在启动"
    AgentLifecycle.RUNNING -> "正在运行"
    AgentLifecycle.WAITING_APPROVAL -> "等待批准"
    AgentLifecycle.WAITING_ANSWER -> "等待回答"
    AgentLifecycle.SUCCEEDED -> "任务完成"
    AgentLifecycle.FAILED -> "任务失败"
    AgentLifecycle.INTERRUPTED -> "已中断"
    AgentLifecycle.OFFLINE -> "离线"
    AgentLifecycle.IDLE, null -> "空闲"
}

private fun statusColor(lifecycle: AgentLifecycle?): Color = when (lifecycle) {
    AgentLifecycle.WAITING_APPROVAL -> AgentGridColors.Orange
    AgentLifecycle.WAITING_ANSWER -> AgentGridColors.Amber
    AgentLifecycle.SUCCEEDED -> AgentGridColors.Green
    AgentLifecycle.FAILED -> AgentGridColors.Red
    AgentLifecycle.INTERRUPTED, AgentLifecycle.OFFLINE -> AgentGridColors.Muted
    else -> AgentGridColors.Blue
}

private fun formatElapsed(milliseconds: Long): String {
    val total = milliseconds / 1_000
    val minutes = total / 60
    val seconds = total % 60
    return "%02d:%02d".format(minutes, seconds)
}

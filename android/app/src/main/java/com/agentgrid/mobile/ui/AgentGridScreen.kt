package com.agentgrid.mobile.ui

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.zIndex
import com.agentgrid.mobile.AgentGridUiState
import com.agentgrid.mobile.ScreenBrightnessPolicy
import com.agentgrid.mobile.SoundEngine
import com.agentgrid.mobile.TaskSoundTracker
import com.agentgrid.mobile.domain.AgentActivity
import com.agentgrid.mobile.domain.AgentLifecycle
import com.agentgrid.mobile.domain.AgentSource
import com.agentgrid.mobile.domain.ControlAction
import com.agentgrid.mobile.domain.PendingRequest
import com.agentgrid.mobile.domain.PendingRequestKind
import com.agentgrid.mobile.domain.QuotaGroup
import com.agentgrid.mobile.domain.SubagentSnapshot
import com.agentgrid.mobile.domain.TaskCapability
import com.agentgrid.mobile.domain.TaskControlIntent
import com.agentgrid.mobile.domain.TaskDashboardProjector
import com.agentgrid.mobile.domain.TaskSnapshot
import com.agentgrid.mobile.domain.UsageSnapshot
import com.agentgrid.mobile.domain.UsageProviderSnapshot
import com.agentgrid.mobile.domain.UsageWindow
import com.agentgrid.mobile.network.LinkState
import com.agentgrid.mobile.render.PixelCoreSurfaceView
import com.agentgrid.mobile.render.PixelRenderState
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

private val EaseOutQuart = CubicBezierEasing(0.25f, 1f, 0.5f, 1f)
private val TaskListAnchorHeight = 1.dp
private const val TaskListAnchorKey = "agentgrid-task-list-anchor"

internal fun taskListAnchorScrollOffsetPx(anchorHeightPx: Int): Int {
    require(anchorHeightPx > 0) { "任务列表锚点高度必须大于零" }
    return anchorHeightPx - 1
}

@Composable
private fun Modifier.newVisibleTaskEntrance(enabled: Boolean): Modifier {
    var settled by remember(enabled) { mutableStateOf(!enabled) }
    val offsetY by animateDpAsState(
        targetValue = if (settled) 0.dp else (-8).dp,
        animationSpec = tween(
            durationMillis = 180,
            easing = EaseOutQuart,
        ),
        label = "新可见任务顶部落位",
    )

    LaunchedEffect(enabled) {
        if (enabled) {
            settled = true
        }
    }

    // 只改变绘制层位置，不参与列表测量，避免和 animateItem 的换位动画互相干扰。
    return graphicsLayer {
        translationY = offsetY.toPx()
    }
}

@Composable
fun AgentGridScreen(
    state: AgentGridUiState,
    onPair: (String) -> Unit,
    onUnpair: () -> Unit,
    onControl: (TaskControlIntent) -> Unit,
    onFocus: (String) -> Unit,
    onToggleDashboard: () -> Unit,
    onActiveTaskBrightnessChange: (Float) -> Unit,
    onIdleBrightnessChange: (Float) -> Unit,
    onExitTerminal: () -> Unit,
) {
    AgentGridTheme {
        AnimatedContent(
            targetState = state.pairing == null,
            transitionSpec = {
                (
                    (
                        fadeIn(tween(180)) +
                            scaleIn(
                                initialScale = 0.985f,
                                animationSpec = tween(210),
                            )
                    ) togetherWith (
                        fadeOut(tween(120)) +
                            scaleOut(
                                targetScale = 0.985f,
                                animationSpec = tween(170),
                            )
                    )
                ).using(SizeTransform(clip = false))
            },
            label = "配对与终端切换",
        ) { isPairing ->
            if (isPairing) {
                PairingScreen(state, onPair)
            } else {
                TaskTerminal(
                    state = state,
                    onUnpair = onUnpair,
                    onControl = onControl,
                    onFocus = onFocus,
                    onToggleDashboard = onToggleDashboard,
                    onActiveTaskBrightnessChange = onActiveTaskBrightnessChange,
                    onIdleBrightnessChange = onIdleBrightnessChange,
                    onExitTerminal = onExitTerminal,
                )
            }
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
        // 横屏下拉开取景框与操作说明，避免两块内容视觉粘连。
        horizontalArrangement = Arrangement.spacedBy(48.dp),
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
                "AGENTPAGER",
                color = AgentGridColors.Text,
                fontSize = 30.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 2.sp,
            )
            Spacer(Modifier.height(10.dp))
            Text("扫描 Mac 上的二维码", color = AgentGridColors.Cyan, fontSize = 16.sp)
            Spacer(Modifier.height(8.dp))
            Text(
                "在 Mac 上打开 AgentGrid Bridge → 连接，\n扫描其中显示的二维码",
                color = AgentGridColors.Muted,
                fontSize = 12.sp,
                lineHeight = 18.sp,
            )
            Spacer(Modifier.height(18.dp))
            OutlinedTextField(
                value = manualText,
                onValueChange = { manualText = it },
                label = { Text("无法扫码？粘贴 Mac 端配对文本") },
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
            AnimatedVisibility(
                visible = state.pairingError != null,
                enter = fadeIn(tween(180)) +
                    scaleIn(
                        initialScale = 0.985f,
                        animationSpec = tween(210),
                    ),
                exit = fadeOut(tween(120)) +
                    scaleOut(
                        targetScale = 0.985f,
                        animationSpec = tween(170),
                    ),
            ) {
                Column {
                    Spacer(Modifier.height(10.dp))
                    Text(
                        state.pairingError.orEmpty(),
                        color = AgentGridColors.Red,
                        fontSize = 12.sp,
                    )
                }
            }
        }
    }
}

@Composable
private fun TaskTerminal(
    state: AgentGridUiState,
    onUnpair: () -> Unit,
    onControl: (TaskControlIntent) -> Unit,
    onFocus: (String) -> Unit,
    onToggleDashboard: () -> Unit,
    onActiveTaskBrightnessChange: (Float) -> Unit,
    onIdleBrightnessChange: (Float) -> Unit,
    onExitTerminal: () -> Unit,
) {
    val projection = state.taskProjection
    val tasks = projection.orderedTasks
    val showDashboard = projection.dashboardVisible
    val automaticallyExpandedTask = tasks.firstOrNull {
        it.id == projection.automaticallyExpandedTaskID
    }
    var expandedTaskID by remember { mutableStateOf<String?>(null) }
    var settingsVisible by remember { mutableStateOf(false) }
    var topControlsHeightPx by remember { mutableStateOf(0) }
    val taskTopInset = with(LocalDensity.current) { topControlsHeightPx.toDp() } + 2.dp
    val visibleTasks = projection.visibleTasks
    val enteringVisibleTaskIDs = projection.enteringVisibleTaskIDs
    val taskListAnchorHeightPx = with(LocalDensity.current) {
        TaskListAnchorHeight.roundToPx()
    }
    val taskListState = rememberLazyListState(
        initialFirstVisibleItemIndex = 0,
        initialFirstVisibleItemScrollOffset = taskListAnchorScrollOffsetPx(
            taskListAnchorHeightPx,
        ),
    )
    val context = LocalContext.current
    val sound = remember(context) { SoundEngine(context.applicationContext) }
    val soundTracker = remember { TaskSoundTracker() }
    var soundEnabled by remember(sound) { mutableStateOf(sound.isEnabled) }

    DisposableEffect(sound) {
        onDispose(sound::close)
    }

    LaunchedEffect(
        automaticallyExpandedTask?.id,
        automaticallyExpandedTask?.lifecycle,
        automaticallyExpandedTask?.subagents?.map { it.id to it.lifecycle },
    ) {
        if (automaticallyExpandedTask != null) {
            expandedTaskID = automaticallyExpandedTask.id
        }
    }
    LaunchedEffect(tasks.map { Triple(it.id, it.lifecycle, it.isMuted) }) {
        soundTracker.nextCue(tasks, soundEnabled)?.let(sound::play)
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AgentGridColors.Background),
    ) {
        TopControls(
            usage = if (showDashboard) {
                null
            } else {
                state.usage
            },
            usageProviders = if (showDashboard) {
                emptyList()
            } else {
                state.usageProviders
            },
            settingsVisible = settingsVisible,
            dashboardVisible = showDashboard,
            onToggleDashboard = {
                onToggleDashboard()
                settingsVisible = false
            },
            onToggleSettings = { settingsVisible = !settingsVisible },
            modifier = Modifier
                .align(Alignment.TopEnd)
                .onSizeChanged { topControlsHeightPx = it.height }
                .zIndex(2f),
        )

        AnimatedContent(
            targetState = showDashboard,
            transitionSpec = {
                (
                    (
                        fadeIn(tween(180)) +
                            scaleIn(
                                initialScale = 0.985f,
                                animationSpec = tween(210),
                            )
                    ) togetherWith (
                        fadeOut(tween(120)) +
                            scaleOut(
                                targetScale = 0.985f,
                                animationSpec = tween(170),
                            )
                    )
                ).using(SizeTransform(clip = false))
            },
            modifier = Modifier
                .align(Alignment.Center)
                .padding(top = if (showDashboard) 0.dp else taskTopInset),
            label = "任务态与状态态切换",
        ) { isDashboardVisible ->
            if (isDashboardVisible) {
                UsageDashboard(
                    usage = state.usage,
                    usageProviders = state.usageProviders,
                    connected = state.linkState == LinkState.CONNECTED,
                )
            } else {
                LazyColumn(
                    state = taskListState,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp)
                        .heightIn(max = 306.dp),
                    verticalArrangement = Arrangement.spacedBy(0.dp),
                ) {
                    item(key = TaskListAnchorKey) {
                        // 保留一个物理像素在视口内，让这个固定项承担 LazyColumn 的滚动锚点。
                        Spacer(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(TaskListAnchorHeight),
                        )
                    }
                    itemsIndexed(
                        items = visibleTasks,
                        key = { _, task -> task.id },
                    ) { index, task ->
                        val entersFromTop = remember(task.id) {
                            task.id in enteringVisibleTaskIDs
                        }
                        val pending = state.pendingRequests.filter {
                            it.taskID == task.id
                        }
                        TaskRow(
                            modifier = Modifier
                                // 自动置顶的任务在换位期间保持前景层，避免从原首行下方穿过。
                                .zIndex(
                                    if (task.id == automaticallyExpandedTask?.id) 1f else 0f,
                                )
                                .animateItem(
                                    fadeInSpec = tween(
                                        durationMillis = 180,
                                        easing = EaseOutQuart,
                                    ),
                                    placementSpec = spring(
                                        // 临界阻尼让远距离换位自然多用一点时间，同时避免回弹。
                                        dampingRatio = 1f,
                                        stiffness = 520f,
                                    ),
                                    fadeOutSpec = tween(120),
                                )
                                .newVisibleTaskEntrance(entersFromTop),
                            task = task,
                            pending = pending,
                            expanded = expandedTaskID == task.id,
                            dimmed = projection.urgentTaskID != null &&
                                projection.urgentTaskID != task.id,
                            showDivider = index < visibleTasks.lastIndex,
                            onClick = {
                                val willExpand = expandedTaskID != task.id
                                expandedTaskID = if (willExpand) task.id else null
                                if (task.isUnread) {
                                    onControl(
                                        TaskControlIntent(task.id, ControlAction.MARK_READ),
                                    )
                                }
                                onFocus(task.id)
                            },
                            onControl = onControl,
                        )
                    }
                }
            }
        }

        AnimatedVisibility(
            visible = settingsVisible,
            enter = fadeIn(tween(140)),
            exit = fadeOut(tween(110)),
            modifier = Modifier
                .align(Alignment.TopEnd)
                .zIndex(1f)
                .padding(top = 42.dp, end = 18.dp),
        ) {
            SettingsPanel(
                state = state,
                soundEnabled = soundEnabled,
                onActiveTaskBrightnessChange = onActiveTaskBrightnessChange,
                onIdleBrightnessChange = onIdleBrightnessChange,
                onSoundEnabledChange = { enabled ->
                    sound.setEnabled(enabled)
                    soundEnabled = enabled
                },
                onUnpair = onUnpair,
                onExitTerminal = onExitTerminal,
            )
        }

        AnimatedVisibility(
            visible = state.linkState != LinkState.CONNECTED,
            enter = fadeIn(tween(140)) +
                slideInVertically(tween(140)) { fullHeight -> fullHeight / 2 },
            exit = fadeOut(tween(110)) +
                slideOutVertically(tween(110)) { fullHeight -> fullHeight / 2 },
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .padding(bottom = 10.dp),
        ) {
            Text(
                "BRIDGE OFFLINE · 正在重连",
                color = AgentGridColors.Dimmed,
                fontSize = 10.sp,
                letterSpacing = 1.sp,
            )
        }
    }
}

@Composable
private fun TopControls(
    usage: UsageSnapshot?,
    usageProviders: List<UsageProviderSnapshot> = emptyList(),
    settingsVisible: Boolean,
    dashboardVisible: Boolean,
    onToggleDashboard: () -> Unit,
    onToggleSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val sections = UsagePresentation.topQuotaSections(usage, usageProviders)
    Row(
        modifier = modifier.padding(start = 18.dp, top = 6.dp, end = 18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (sections.isNotEmpty()) {
            Row(
                modifier = Modifier
                    .weight(1f, fill = false)
                    .horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                sections.forEach { section ->
                    UsageProviderBank(section)
                }
            }
        }
        Box(
            modifier = Modifier
                .size(28.dp)
                .clickable(onClick = onToggleDashboard)
                .semantics {
                    contentDescription = if (dashboardVisible) {
                        "切换到任务列表"
                    } else {
                        "切换到状态显示栏"
                    }
            },
            contentAlignment = Alignment.Center,
        ) {
            ViewSwitchIcon(showTaskIcon = dashboardVisible)
        }
        Box(
            modifier = Modifier
                .size(28.dp)
                .clickable(onClick = onToggleSettings)
                .semantics {
                    contentDescription = if (settingsVisible) "关闭设置" else "打开设置"
                },
            contentAlignment = Alignment.Center,
        ) {
            Text(
                if (settingsVisible) "×" else "⚙",
                color = if (settingsVisible) AgentGridColors.Amber else AgentGridColors.Muted,
                fontSize = 13.sp,
                fontWeight = FontWeight.Bold,
            )
        }
    }
}

@Composable
private fun ViewSwitchIcon(showTaskIcon: Boolean) {
    Canvas(modifier = Modifier.size(12.dp)) {
        val unit = size.minDimension / 16f

        fun pixelRect(x: Float, y: Float, width: Float, height: Float) {
            drawRect(
                color = AgentGridColors.Muted,
                topLeft = Offset(x * unit, y * unit),
                size = Size(width * unit, height * unit),
            )
        }

        if (showTaskIcon) {
            // 三行任务列表：左侧状态格，右侧信息条。
            listOf(1f, 7f, 13f).forEach { y ->
                pixelRect(x = 0f, y = y, width = 3f, height = 3f)
                pixelRect(x = 5f, y = y, width = 11f, height = 3f)
            }
        } else {
            // 三档状态柱：用硬直角高度差表示状态总览。
            pixelRect(x = 0f, y = 10f, width = 4f, height = 6f)
            pixelRect(x = 6f, y = 6f, width = 4f, height = 10f)
            pixelRect(x = 12f, y = 1f, width = 4f, height = 15f)
        }
    }
}

@Composable
private fun UsageProviderBank(section: TopQuotaSection) {
    Row(
        modifier = Modifier
            .background(AgentGridColors.Surface)
            .padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Text(
                section.title,
                color = AgentGridColors.Cyan,
                fontSize = 8.sp,
                lineHeight = 9.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 0.5.sp,
                maxLines = 1,
            )
            section.items.firstOrNull { it.statusText != null }?.let { item ->
                Text(
                    item.statusText.orEmpty(),
                    color = glmHealthToneColor(item.statusTone),
                    fontSize = 7.sp,
                    lineHeight = 9.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                )
            }
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            section.items.forEachIndexed { index, item ->
                if (index > 0) {
                    Box(
                        Modifier.width(1.dp).height(16.dp).background(AgentGridColors.Divider),
                    )
                }
                UsageBank(item, section.title, section.showGroupTitles)
            }
        }
    }
}

@Composable
private fun UsageBank(item: TopQuotaItem, providerTitle: String, showGroupTitle: Boolean) {
    val group = item.group
    val windows = group.windows.sortedBy { it.windowMinutes }.take(2)
    if (windows.isEmpty()) return
    val title = UsagePresentation.quotaTitle(group)
    Row(
        modifier = Modifier
            .semantics(mergeDescendants = true) {
                contentDescription = buildString {
                    append(providerTitle)
                    if (showGroupTitle) append("，$title")
                    item.statusText?.let { append("，$it") }
                    windows.forEach { window ->
                        append("，${window.label} 剩余 ")
                        append(window.remainingPercentage.roundToInt().coerceIn(0, 100))
                        append('%')
                    }
                }
            },
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (showGroupTitle) {
            Text(
                UsagePresentation.compactQuotaTitle(group),
                color = when (UsagePresentation.quotaAccent(group)) {
                    QuotaAccent.VIOLET -> AgentGridColors.Violet
                    QuotaAccent.CYAN -> AgentGridColors.Cyan
                    QuotaAccent.MUTED -> AgentGridColors.Muted
                },
                fontSize = 8.sp,
                lineHeight = 8.sp,
                fontWeight = FontWeight.Medium,
                letterSpacing = 0.25.sp,
                maxLines = 1,
            )
        }
        windows.forEach { window ->
            UsageGauge(
                window = window,
            )
        }
    }
}

@Composable
private fun UsageGauge(
    window: UsageWindow,
    modifier: Modifier = Modifier,
) {
    val remaining = window.remainingPercentage.roundToInt().coerceIn(0, 100)
    val color = when {
        remaining < 10 -> AgentGridColors.Red
        remaining < 20 -> AgentGridColors.Orange
        else -> AgentGridColors.Cyan
    }
    Column(
        modifier = modifier.widthIn(min = 52.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                UsagePresentation.compactWindowLabel(window),
                color = AgentGridColors.Muted,
                fontSize = 8.sp,
                lineHeight = 10.sp,
                fontWeight = FontWeight.Medium,
                letterSpacing = 0.25.sp,
                maxLines = 1,
            )
            Text(
                "$remaining%",
                color = color,
                fontSize = 11.sp,
                lineHeight = 11.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 0.25.sp,
                maxLines = 1,
            )
        }
        LinearProgressIndicator(
            progress = { remaining / 100f },
            modifier = Modifier
                .width(52.dp)
                .height(2.dp),
            color = color,
            trackColor = AgentGridColors.Divider,
            gapSize = 0.dp,
            drawStopIndicator = {},
        )
    }
}

@Composable
private fun TaskRow(
    modifier: Modifier = Modifier,
    task: TaskSnapshot,
    pending: List<PendingRequest>,
    expanded: Boolean,
    dimmed: Boolean,
    showDivider: Boolean,
    onClick: () -> Unit,
    onControl: (TaskControlIntent) -> Unit,
) {
    val rowAlpha by animateFloatAsState(
        targetValue = if (dimmed) 0.34f else 1f,
        animationSpec = tween(180),
        label = "任务行注意力",
    )
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(if (expanded) AgentGridColors.Surface else Color.Transparent)
            .clickable(onClick = onClick)
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
                            // 模拟器重复点击同一状态时也应从头播放；真实任务不随普通内容更新重置。
                            revision = if (task.id == "agentgrid-simulator") task.updatedAt else 0,
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
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                Text(
                    task.title,
                    color = AgentGridColors.Text.copy(alpha = rowAlpha),
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (shouldShowTokenSummary(task)) {
                    Text(
                        "TOKEN  ${tokenDetailsText(task)}",
                        color = AgentGridColors.Cyan.copy(alpha = rowAlpha),
                        fontSize = 10.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.offset(y = (-1).dp),
                    )
                } else {
                    Column(
                        modifier = Modifier.offset(y = (-2).dp),
                        verticalArrangement = Arrangement.spacedBy(0.dp),
                    ) {
                        Text(
                            task.userPrompt?.let { "你：$it" } ?: "你：—",
                            color = AgentGridColors.Muted.copy(alpha = rowAlpha),
                            fontSize = 11.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        CommandTicker(
                            text = taskActivitySummary(task),
                            color = statusColor(task).copy(alpha = rowAlpha),
                        )
                    }
                }
            }

            TaskMeta(task = task, alpha = rowAlpha)
        }

        AnimatedVisibility(
            visible = expanded,
            enter = expandVertically(
                animationSpec = tween(
                    durationMillis = 280,
                    easing = EaseOutQuart,
                ),
                expandFrom = Alignment.Top,
            ) + fadeIn(
                animationSpec = tween(
                    durationMillis = 180,
                    delayMillis = 35,
                    easing = EaseOutQuart,
                ),
            ),
            exit = shrinkVertically(
                animationSpec = tween(
                    durationMillis = 190,
                    easing = EaseOutQuart,
                ),
                shrinkTowards = Alignment.Top,
            ) + fadeOut(tween(120)),
        ) {
            TaskDetails(
                task = task,
                pending = pending,
                onControl = onControl,
            )
        }

        if (showDivider) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(start = 78.dp, end = 4.dp)
                    .height(1.dp)
                    .background(AgentGridColors.Divider.copy(alpha = 0.85f)),
            )
        }
    }
}

@Composable
private fun CommandTicker(
    text: String,
    color: Color,
) {
    AnimatedContent(
        targetState = text,
        transitionSpec = {
            (
                (
                    slideInVertically(
                        animationSpec = tween(
                            durationMillis = 220,
                            easing = EaseOutQuart,
                        ),
                    ) { fullHeight -> fullHeight } +
                        fadeIn(
                            animationSpec = tween(
                                durationMillis = 160,
                                easing = EaseOutQuart,
                            ),
                        )
                ) togetherWith (
                    slideOutVertically(
                        animationSpec = tween(
                            durationMillis = 160,
                            easing = EaseOutQuart,
                        ),
                    ) { fullHeight -> -fullHeight } +
                        fadeOut(tween(110))
                )
            ).using(SizeTransform(clip = true))
        },
        contentAlignment = Alignment.CenterStart,
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 19.dp)
            .offset(y = (-3).dp),
        label = "AI 命令更新",
    ) { currentText ->
        Text(
            currentText,
            color = color,
            fontSize = 10.sp,
            lineHeight = 14.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

@Composable
private fun TaskMeta(task: TaskSnapshot, alpha: Float) {
    val elapsed by produceState(
        initialValue = task.elapsedAt(System.currentTimeMillis()),
        task.id,
        task.lifecycle,
        task.startedAt,
        task.updatedAt,
        task.completedAt,
    ) {
        if (!task.isTerminal) {
            while (true) {
                value = task.elapsedAt(System.currentTimeMillis())
                delay(1_000)
            }
        }
    }
    Column(
        modifier = Modifier.widthIn(min = 166.dp, max = 210.dp),
        horizontalAlignment = Alignment.End,
        verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            MetaTag(agentBadge(task.source), agentBadgeColor(task.source), alpha)
            MetaTag(
                agentOriginLabel(task.source),
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
    pending: List<PendingRequest>,
    onControl: (TaskControlIntent) -> Unit,
) {
    var answer by remember(task.id) { mutableStateOf("") }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = 250.dp)
            .verticalScroll(rememberScrollState())
            .padding(start = 82.dp, end = 18.dp, bottom = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        if (task.subagents.isNotEmpty()) {
            SubagentPanel(task.subagents)
        }
        task.tokenUsage?.let {
            DetailLine(
                "TOKEN",
                tokenDetailsText(task),
                AgentGridColors.Cyan,
            )
        }
        AnimatedContent(
            targetState = pending,
            contentKey = { requests -> requests.map { it.requestID to it.kind } },
            transitionSpec = {
                (
                    (
                        fadeIn(tween(180)) +
                            scaleIn(
                                initialScale = 0.985f,
                                animationSpec = tween(210),
                            )
                    ) togetherWith (
                        fadeOut(tween(120)) +
                            scaleOut(
                                targetScale = 0.985f,
                                animationSpec = tween(170),
                            )
                    )
                ).using(SizeTransform(clip = false))
            },
            label = "待处理请求切换",
        ) { targetRequests ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                targetRequests.forEach { targetPending ->
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        targetPending.summary?.let { summary ->
                            DetailLine(
                                if (targetPending.kind == PendingRequestKind.APPROVAL) {
                                    "APPROVAL"
                                } else {
                                    "QUESTION"
                                },
                                summary,
                                if (targetPending.kind == PendingRequestKind.APPROVAL) {
                                    AgentGridColors.Amber
                                } else {
                                    AgentGridColors.Yellow
                                },
                            )
                        }

                        if (
                            targetPending.kind == PendingRequestKind.APPROVAL &&
                            TaskCapability.APPROVE in task.capabilities
                        ) {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                PixelButton("允许", AgentGridColors.Green) {
                                    targetPending.controlIntent(ControlAction.APPROVE)
                                        ?.let(onControl)
                                }
                                PixelButton("拒绝", AgentGridColors.Red) {
                                    targetPending.controlIntent(ControlAction.DENY)
                                        ?.let(onControl)
                                }
                            }
                        } else if (
                            targetPending.kind == PendingRequestKind.QUESTION &&
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
                                    onControl(
                                        TaskControlIntent(
                                            taskID = task.id,
                                            action = ControlAction.ANSWER,
                                            value = answer,
                                        ),
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SubagentPanel(subagents: List<SubagentSnapshot>) {
    val now by produceState(
        initialValue = System.currentTimeMillis(),
        key1 = subagents.map { it.id to it.lifecycle },
    ) {
        while (true) {
            value = System.currentTimeMillis()
            delay(1_000)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(AgentGridColors.SurfaceRaised)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(9.dp),
    ) {
        Text(
            "CODEX (${subagents.size})",
            color = AgentGridColors.Muted,
            fontSize = 10.sp,
            fontWeight = FontWeight.Bold,
        )
        subagents.forEach { subagent ->
            key(subagent.id) {
                SubagentRow(subagent, now)
            }
        }
    }
}

@Composable
private fun SubagentRow(
    subagent: SubagentSnapshot,
    now: Long,
) {
    val color = lifecycleColor(subagent.lifecycle, subagent.activity)
    Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Box(
                modifier = Modifier
                    .size(6.dp)
                    .background(color),
            )
            Text(
                subagent.displayName,
                color = AgentGridColors.Text,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            subagent.tokenUsage?.takeIf { it.total > 0 }?.let {
                Text(
                    formatTokens(it.total),
                    color = AgentGridColors.Muted,
                    fontSize = 8.sp,
                )
            }
            Text(
                "${statusText(subagent.lifecycle)} · ${formatElapsed(subagent.elapsedAt(now))}",
                color = color,
                fontSize = 9.sp,
            )
        }
        Text(
            "└ ${subagent.latestStep ?: activityText(subagent.activity)}",
            color = AgentGridColors.Muted,
            fontSize = 9.sp,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(start = 14.dp),
        )
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
    soundEnabled: Boolean,
    onActiveTaskBrightnessChange: (Float) -> Unit,
    onIdleBrightnessChange: (Float) -> Unit,
    onSoundEnabledChange: (Boolean) -> Unit,
    onUnpair: () -> Unit,
    onExitTerminal: () -> Unit,
) {
    Column(
        modifier = Modifier
            .width(206.dp)
            .fillMaxHeight()
            .background(AgentGridColors.Surface)
            .verticalScroll(rememberScrollState())
            .padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text("设置", color = AgentGridColors.Text, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        DetailLine(
            "LINK",
            if (state.linkState == LinkState.CONNECTED) "已连接" else "正在重连",
            if (state.linkState == LinkState.CONNECTED) AgentGridColors.Green else AgentGridColors.Red,
        )
        DetailLine("TASK", "${state.taskProjection.orderedTasks.size}", AgentGridColors.Cyan)
        BrightnessSlider(
            label = "任务亮度",
            value = state.activeTaskBrightness,
            onValueChange = onActiveTaskBrightnessChange,
            semanticDescription = "有任务时的屏幕亮度",
        )
        BrightnessSlider(
            label = "空闲亮度",
            value = state.idleBrightness,
            onValueChange = onIdleBrightnessChange,
            semanticDescription = "空闲和任务结束时的屏幕亮度",
        )
        PixelButton(
            if (soundEnabled) "提示音：开" else "提示音：关",
            if (soundEnabled) AgentGridColors.Green else AgentGridColors.Muted,
        ) {
            onSoundEnabledChange(!soundEnabled)
        }
        PixelButton("解除配对", AgentGridColors.Red, onUnpair)
        PixelButton("退出专用模式", AgentGridColors.Muted, onExitTerminal)
    }
}

@Composable
private fun BrightnessSlider(
    label: String,
    value: Float,
    onValueChange: (Float) -> Unit,
    semanticDescription: String,
) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(label, color = AgentGridColors.Text, fontSize = 10.sp)
            Text(
                "${(value * 100).roundToInt()}%",
                color = AgentGridColors.Cyan,
                fontSize = 10.sp,
                fontWeight = FontWeight.Bold,
            )
        }
        Slider(
            value = value,
            onValueChange = onValueChange,
            valueRange = ScreenBrightnessPolicy.MIN_BRIGHTNESS..
                ScreenBrightnessPolicy.MAX_BRIGHTNESS,
            colors = SliderDefaults.colors(
                thumbColor = AgentGridColors.Cyan,
                activeTrackColor = AgentGridColors.Cyan,
                inactiveTrackColor = AgentGridColors.Dimmed,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .semantics {
                    contentDescription = semanticDescription
                },
        )
    }
}

@Preview(
    name = "亮度设置",
    widthDp = 240,
    heightDp = 360,
    showBackground = true,
)
@Composable
private fun BrightnessSettingsPreview() {
    AgentGridTheme {
        SettingsPanel(
            state = AgentGridUiState(linkState = LinkState.CONNECTED),
            soundEnabled = true,
            onActiveTaskBrightnessChange = {},
            onIdleBrightnessChange = {},
            onSoundEnabledChange = {},
            onUnpair = {},
            onExitTerminal = {},
        )
    }
}

@Preview(
    name = "协议来源兼容",
    widthDp = 240,
    heightDp = 96,
    showBackground = true,
    backgroundColor = 0xFF03070B,
)
@Composable
private fun AgentSourceCompatibilityPreview() {
    AgentGridTheme {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            listOf(AgentSource.ZCODE, AgentSource.UNKNOWN).forEach { source ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    MetaTag(agentBadge(source), agentBadgeColor(source), 1f)
                    MetaTag(agentOriginLabel(source), AgentGridColors.Muted, 1f)
                }
            }
        }
    }
}

@Preview(
    name = "ZCode 核心会话活动",
    widthDp = 360,
    heightDp = 320,
    showBackground = true,
    backgroundColor = 0xFF03070B,
)
@Composable
private fun ZCodeCoreSessionActivityPreview() {
    val base = TaskSnapshot(
        id = "zcode-preview",
        source = AgentSource.ZCODE,
        projectName = "AgentPager",
        title = "AgentPager · 检查 Hook 会话监控",
        lifecycle = AgentLifecycle.STARTING,
        activity = AgentActivity.THINKING,
        startedAt = 1,
        updatedAt = 2,
    )
    val tasks = listOf(
        base,
        base.copy(
            id = "zcode-thinking",
            lifecycle = AgentLifecycle.RUNNING,
        ),
        base.copy(
            id = "zcode-tool",
            lifecycle = AgentLifecycle.RUNNING,
            activity = AgentActivity.READING,
            latestStep = "读取文件",
        ),
        base.copy(
            id = "zcode-idle",
            lifecycle = AgentLifecycle.IDLE,
            activity = null,
        ),
    )

    AgentGridTheme {
        Column(modifier = Modifier.background(AgentGridColors.Background)) {
            tasks.forEachIndexed { index, task ->
                TaskRow(
                    task = task,
                    pending = emptyList(),
                    expanded = false,
                    dimmed = false,
                    showDivider = index < tasks.lastIndex,
                    onClick = {},
                    onControl = {},
                )
            }
        }
    }
}

@Preview(
    name = "ZCode waitingApproval",
    widthDp = 360,
    heightDp = 220,
    showBackground = true,
    backgroundColor = 0xFF03070B,
)
@Composable
private fun ZCodeWaitingApprovalPreview() {
    val task = TaskSnapshot(
        id = "zcode-approval-preview",
        source = AgentSource.ZCODE,
        projectName = "AgentPager",
        title = "AgentPager · 处理工具审批",
        lifecycle = AgentLifecycle.WAITING_APPROVAL,
        startedAt = 1,
        updatedAt = 2,
        capabilities = setOf(TaskCapability.APPROVE, TaskCapability.DENY),
    )
    val pending = PendingRequest(
        taskID = task.id,
        requestID = "zcode:fixture-request",
        kind = PendingRequestKind.APPROVAL,
        summary = "读取文件 · 等待手机批准",
    )

    AgentGridTheme {
        Box(modifier = Modifier.background(AgentGridColors.Background)) {
            TaskRow(
                task = task,
                pending = listOf(pending),
                expanded = true,
                dimmed = false,
                showDivider = false,
                onClick = {},
                onControl = {},
            )
        }
    }
}

@Preview(
    name = "顶部额度 · CODEX 与 GLM 分组",
    widthDp = 720,
    heightDp = 64,
    showBackground = true,
    backgroundColor = 0xFF03070B,
)
@Composable
private fun AllQuotaProvidersPreview() {
    QuotaTopControlsPreview(
        usage = previewCodexUsage(),
        providers = listOf(previewGLMProvider()),
    )
}

@Preview(
    name = "顶部额度 · 只有 GLM",
    widthDp = 360,
    heightDp = 64,
    showBackground = true,
    backgroundColor = 0xFF03070B,
)
@Composable
private fun GLMOnlyQuotaPreview() {
    QuotaTopControlsPreview(
        usage = null,
        providers = listOf(previewGLMProvider()),
    )
}

@Preview(
    name = "顶部额度 · 没有 GLM",
    widthDp = 480,
    heightDp = 64,
    showBackground = true,
    backgroundColor = 0xFF03070B,
)
@Composable
private fun NoGLMQuotaPreview() {
    QuotaTopControlsPreview(
        usage = previewCodexUsage(),
        providers = emptyList(),
    )
}

@Preview(
    name = "顶部额度 · 360dp 横滑与固定按钮",
    widthDp = 360,
    heightDp = 64,
    showBackground = true,
    backgroundColor = 0xFF03070B,
)
@Composable
private fun NarrowAllQuotaProvidersPreview() {
    QuotaTopControlsPreview(
        usage = previewCodexUsage(),
        providers = listOf(previewGLMProvider()),
    )
}

@Preview(
    name = "顶部额度 · GLM 陈旧读数",
    widthDp = 650,
    heightDp = 80,
    showBackground = true,
    backgroundColor = 0xFF03070B,
)
@Composable
private fun StaleQuotaProvidersPreview() {
    QuotaTopControlsPreview(
        usage = previewCodexUsage(),
        providers = listOf(previewGLMProvider().copy(status = "stale_timeout")),
    )
}

@Preview(
    name = "顶部额度 · 大字体与 100%",
    widthDp = 720,
    heightDp = 80,
    fontScale = 1.5f,
    showBackground = true,
    backgroundColor = 0xFF03070B,
)
@Composable
private fun LargeFontQuotaProvidersPreview() {
    QuotaTopControlsPreview(
        usage = previewCodexUsage(),
        providers = listOf(previewGLMProvider()),
    )
}

@Preview(
    name = "顶部额度 · 无额度",
    widthDp = 360,
    heightDp = 64,
    showBackground = true,
    backgroundColor = 0xFF03070B,
)
@Composable
private fun EmptyQuotaProvidersPreview() {
    QuotaTopControlsPreview(usage = null, providers = emptyList())
}

@Preview(
    name = "主页 · 横屏额度与五条任务",
    widthDp = 800,
    heightDp = 360,
    showBackground = true,
)
@Composable
private fun QuotaTaskTerminalPreview() {
    val now = System.currentTimeMillis()
    val task = TaskSnapshot(
        id = "quota-layout-preview",
        source = AgentSource.CODEX_CLI,
        projectName = "AgentPager",
        title = "AgentPager · 检查额度显示",
        lifecycle = AgentLifecycle.RUNNING,
        activity = AgentActivity.READING,
        latestStep = "检查额度分组与布局",
        startedAt = now - 300_000,
        updatedAt = now,
    )
    AgentGridTheme {
        TaskTerminal(
            state = AgentGridUiState(
                linkState = LinkState.CONNECTED,
                taskProjection = TaskDashboardProjector.project(
                    tasks = listOf(task) + (2..5).map { index ->
                        task.copy(id = "quota-task-$index", title = "AgentPager · 查看任务 $index")
                    },
                    preferredFocusedTaskID = task.id,
                    previous = null,
                    now = now,
                ).copy(automaticallyExpandedTaskID = task.id),
                usage = previewCodexUsage(),
                usageProviders = listOf(previewGLMProvider()),
            ),
            onUnpair = {},
            onControl = {},
            onFocus = {},
            onToggleDashboard = {},
            onActiveTaskBrightnessChange = {},
            onIdleBrightnessChange = {},
            onExitTerminal = {},
        )
    }
}

@Composable
private fun QuotaTopControlsPreview(
    usage: UsageSnapshot?,
    providers: List<UsageProviderSnapshot>,
) {
    AgentGridTheme {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(AgentGridColors.Background),
        ) {
            TopControls(
                usage = usage,
                usageProviders = providers,
                settingsVisible = false,
                dashboardVisible = false,
                onToggleDashboard = {},
                onToggleSettings = {},
                modifier = Modifier.align(Alignment.TopEnd),
            )
        }
    }
}

private fun previewCodexUsage() = UsageSnapshot(
    quotaGroups = listOf(
        QuotaGroup(
            id = "codex",
            windows = listOf(
                previewUsageWindow("WEEK", 10_080, 95.0),
            ),
        ),
        QuotaGroup(
            id = "codex_bengalfox",
            name = "GPT-5.3-Codex-Spark",
            windows = listOf(
                previewUsageWindow("5H", 300, 88.0),
                previewUsageWindow("WEEK", 10_080, 71.0),
            ),
        ),
    ),
)

private fun previewGLMProvider() = UsageProviderSnapshot(
    id = "glm",
    displayName = "GLM",
    planName = "GLM Coding Plan",
    status = "available",
    quotaGroups = listOf(
        QuotaGroup(
            id = "credit",
            windows = listOf(
                previewUsageWindow("5H", 300, 100.0),
                previewUsageWindow("WEEK", 10_080, 99.0),
            ),
        ),
    ),
)

private fun previewUsageWindow(
    label: String,
    windowMinutes: Int,
    remainingPercentage: Double,
) = UsageWindow(
    key = label.lowercase(),
    label = label,
    usedPercentage = 100 - remainingPercentage,
    remainingPercentage = remainingPercentage,
    windowMinutes = windowMinutes,
)

internal fun statusText(lifecycle: AgentLifecycle): String = when (lifecycle) {
    AgentLifecycle.OFFLINE -> "离线"
    AgentLifecycle.IDLE -> "空闲"
    AgentLifecycle.STARTING -> "正在启动"
    AgentLifecycle.RUNNING -> "正在运行"
    AgentLifecycle.WAITING_APPROVAL -> "等待批准"
    AgentLifecycle.WAITING_ANSWER -> "等待回答"
    AgentLifecycle.SUCCEEDED -> "任务完成"
    AgentLifecycle.INTERRUPTED -> "已中断"
}

private fun statusColor(task: TaskSnapshot): Color =
    lifecycleColor(task.lifecycle, task.activity)

private fun lifecycleColor(
    lifecycle: AgentLifecycle,
    activity: AgentActivity?,
): Color = when (lifecycle) {
    AgentLifecycle.WAITING_APPROVAL -> AgentGridColors.Amber
    AgentLifecycle.WAITING_ANSWER -> AgentGridColors.Yellow
    AgentLifecycle.SUCCEEDED -> AgentGridColors.Green
    AgentLifecycle.INTERRUPTED, AgentLifecycle.OFFLINE -> AgentGridColors.Muted
    AgentLifecycle.IDLE -> AgentGridColors.Cyan
    AgentLifecycle.STARTING -> AgentGridColors.Violet
    AgentLifecycle.RUNNING -> when (activity) {
        AgentActivity.READING, AgentActivity.SEARCHING, AgentActivity.BROWSING ->
            AgentGridColors.Cyan
        AgentActivity.EDITING -> AgentGridColors.Indigo
        AgentActivity.EXECUTING -> AgentGridColors.Orange
        AgentActivity.TESTING -> AgentGridColors.Blue
        else -> AgentGridColors.Violet
    }
}

internal fun agentBadge(source: AgentSource): String = when (source) {
    AgentSource.CODEX_DESKTOP, AgentSource.CODEX_CLI -> "Codex"
    AgentSource.CLAUDE_CODE -> "Claude"
    AgentSource.ZCODE -> "ZCode"
    AgentSource.UNKNOWN -> "Agent"
}

private fun agentBadgeColor(source: AgentSource): Color = when (source) {
    AgentSource.CLAUDE_CODE -> AgentGridColors.Violet
    AgentSource.ZCODE -> AgentGridColors.Cyan
    else -> AgentGridColors.Blue
}

internal fun agentOriginLabel(source: AgentSource): String = when (source) {
    AgentSource.CODEX_DESKTOP -> "ChatGPT.app"
    AgentSource.CODEX_CLI -> "Terminal"
    AgentSource.CLAUDE_CODE -> "Claude Code"
    AgentSource.ZCODE -> "ZCode"
    AgentSource.UNKNOWN -> "未知来源"
}

internal fun activityText(activity: AgentActivity?): String = when (activity) {
    AgentActivity.THINKING -> "正在思考"
    AgentActivity.READING -> "正在读取"
    AgentActivity.SEARCHING -> "正在搜索"
    AgentActivity.EDITING -> "正在编辑"
    AgentActivity.EXECUTING -> "正在执行"
    AgentActivity.TESTING -> "正在测试"
    AgentActivity.BROWSING -> "正在浏览"
    AgentActivity.DELEGATING -> "正在协作"
    null -> "等待新步骤"
}

internal fun taskActivitySummary(task: TaskSnapshot): String {
    task.latestStep?.let { return it }
    if (task.lifecycle == AgentLifecycle.STARTING) {
        return statusText(task.lifecycle)
    }
    return task.activity?.let(::activityText) ?: statusText(task.lifecycle)
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

private fun tokenDetailsText(task: TaskSnapshot): String {
    val usage = task.tokenUsage ?: return "—"
    return "IN ${formatTokens(usage.input)} · CACHE ${formatTokens(usage.cachedInput)} · " +
        "OUT ${formatTokens(usage.output)} · TOTAL ${formatTokens(usage.total)}"
}

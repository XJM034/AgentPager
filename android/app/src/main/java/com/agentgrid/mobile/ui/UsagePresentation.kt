package com.agentgrid.mobile.ui

import com.agentgrid.mobile.domain.DailyUsagePoint
import com.agentgrid.mobile.domain.QuotaGroup
import com.agentgrid.mobile.domain.UsageSnapshot
import com.agentgrid.mobile.domain.UsageProviderSnapshot
import com.agentgrid.mobile.domain.UsageWindow
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.ceil
import kotlin.math.roundToInt

internal enum class UsageRange(
    val days: Int,
    val label: String,
) {
    SEVEN_DAYS(7, "7 天"),
    THIRTY_DAYS(30, "30 天"),
    NINETY_DAYS(90, "90 天"),
}

internal enum class QuotaAccent {
    MUTED,
    VIOLET,
    CYAN,
}

internal enum class QuotaProviderTab(val label: String) {
    CODEX("CODEX"),
    GLM("GLM"),
}

internal enum class GLMHealthTone {
    MUTED,
    CYAN,
    ORANGE,
    RED,
}

private enum class GLMFailureReason(
    val staleMessage: String,
    val unavailableMessage: String,
) {
    RATE_LIMITED("请求受限，保留上次可信读数", "请求受限，请稍后重试"),
    TIMEOUT("请求超时，保留上次可信读数", "请求超时，请稍后重试"),
    SERVER_ERROR("上游服务异常，保留上次可信读数", "上游服务暂不可用"),
    NON_JSON("上游响应异常，保留上次可信读数", "上游返回非 JSON 数据"),
    MISSING_FIELDS("上游缺少必要字段，保留上次可信读数", "上游响应缺少必要字段"),
    UNKNOWN_SCHEMA("上游格式变化，保留上次可信读数", "上游响应格式暂不兼容"),
    OTHER("暂时无法刷新，保留上次可信读数", "额度暂不可用"),
}

private fun glmFailureReason(status: String): GLMFailureReason = when {
    status.contains("rate_limited") -> GLMFailureReason.RATE_LIMITED
    status.contains("timeout") -> GLMFailureReason.TIMEOUT
    status.contains("server_error") -> GLMFailureReason.SERVER_ERROR
    status.contains("non_json") -> GLMFailureReason.NON_JSON
    status.contains("missing_fields") -> GLMFailureReason.MISSING_FIELDS
    status.contains("unknown_schema") -> GLMFailureReason.UNKNOWN_SCHEMA
    else -> GLMFailureReason.OTHER
}

internal enum class GLMHealth(
    val text: String,
    val tone: GLMHealthTone,
    val showsTrustedWindows: Boolean,
    val providerTimestampCanBeSuccess: Boolean,
) {
    UNCONFIGURED("未启用", GLMHealthTone.MUTED, false, false),
    AVAILABLE("可用", GLMHealthTone.CYAN, true, true),
    STALE("数据陈旧", GLMHealthTone.ORANGE, true, false),
    AUTHENTICATION_FAILED("鉴权失效", GLMHealthTone.RED, true, false),
    UNAVAILABLE("暂不可用", GLMHealthTone.RED, false, false),
    PLAN_EXPIRED("套餐已过期", GLMHealthTone.RED, false, false),
    EXHAUSTED("额度耗尽", GLMHealthTone.RED, true, false),
    ;

    fun message(status: String): String = when (this) {
        UNCONFIGURED -> "可选连接，不影响 ZCode 会话与手机审批"
        AVAILABLE -> "额度数据可用"
        STALE -> glmFailureReason(status).staleMessage
        AUTHENTICATION_FAILED -> "请在 Mac 上重新连接 GLM 额度；显示的是最后可信读数"
        UNAVAILABLE -> glmFailureReason(status).unavailableMessage
        PLAN_EXPIRED -> "Coding Plan 套餐已过期"
        EXHAUSTED -> "上游明确返回额度耗尽"
    }
}

internal enum class QuotaLevel(
    val text: String,
    val tone: GLMHealthTone,
) {
    NORMAL("额度充足", GLMHealthTone.CYAN),
    LOW("额度偏低", GLMHealthTone.ORANGE),
    CRITICAL("额度告急", GLMHealthTone.RED),
    EXHAUSTED("额度耗尽", GLMHealthTone.RED),
}

internal data class GLMWindowPresentation(
    val label: String,
    val remainingPercentage: Int,
    val resetText: String,
    val level: QuotaLevel,
    val levelText: String,
    val accessibilityText: String,
)

internal data class GLMQuotaDetails(
    val planLabel: String,
    val planLevelRaw: String?,
    val health: GLMHealth,
    val healthText: String,
    val message: String,
    val lastSuccessfulAt: Long?,
    val lastUpdatedAt: Long?,
    val windows: List<GLMWindowPresentation>,
)

internal data class TopQuotaItem(
    val group: QuotaGroup,
    val statusText: String? = null,
    val statusTone: GLMHealthTone? = null,
)

internal data class TopQuotaSection(
    val title: String,
    val items: List<TopQuotaItem>,
    val showGroupTitles: Boolean,
)

internal object UsagePresentation {
    val defaultQuotaTab = QuotaProviderTab.CODEX
    val quotaProviderTabs = QuotaProviderTab.entries

    fun topQuotaGroups(
        usage: UsageSnapshot?,
        providers: List<UsageProviderSnapshot> = emptyList(),
    ): List<QuotaGroup> {
        val groups = usage?.quotaGroups.orEmpty().ifEmpty {
            if (usage?.windows.isNullOrEmpty()) {
                emptyList()
            } else {
                listOf(
                    QuotaGroup(
                        id = usage?.limitID ?: "default",
                        name = usage.limitName,
                        capturedAt = usage.capturedAt,
                        windows = usage?.windows.orEmpty(),
                    ),
                )
            }
        }
        val general = groups.firstOrNull(::isGeneralQuota)
        val spark = groups.firstOrNull(::isSparkQuota)
        val codexGroups = listOfNotNull(general, spark).ifEmpty { groups.take(2) }
        val glmProvider = providers.firstOrNull {
            it.id.equals("glm", ignoreCase = true)
        }
        val glmGroup = glmProvider
            ?.quotaGroups
            ?.firstOrNull { it.windows.isNotEmpty() }
            ?.let { group ->
                group.copy(
                    id = "glm",
                    name = glmProvider.displayName ?: "GLM",
                    capturedAt = group.capturedAt ?: glmProvider.capturedAt,
                )
            }
        return codexGroups + listOfNotNull(glmGroup)
    }

    fun quotaTitle(group: QuotaGroup): String = quotaPresentation(group).title

    fun quotaAccent(group: QuotaGroup): QuotaAccent = quotaPresentation(group).accent

    // Provider headings belong only to the compact home strip; detail names stay intact.
    fun topQuotaSections(
        usage: UsageSnapshot?,
        providers: List<UsageProviderSnapshot> = emptyList(),
    ): List<TopQuotaSection> {
        val items = topQuotaItems(usage, providers).filter { it.group.windows.isNotEmpty() }
        val (glm, codex) = items.partition { it.group.id.equals("glm", ignoreCase = true) }
        return buildList {
            if (codex.isNotEmpty()) add(TopQuotaSection("CODEX", codex, showGroupTitles = true))
            if (glm.isNotEmpty()) add(TopQuotaSection("GLM", glm, showGroupTitles = false))
        }
    }

    fun compactQuotaTitle(group: QuotaGroup): String =
        if (isGeneralQuota(group)) "GEN" else quotaTitle(group)

    fun compactWindowLabel(window: UsageWindow): String = when (window.windowMinutes) {
        300 -> "5h"
        10_080 -> "7d"
        else -> window.label
    }

    fun topQuotaItems(
        usage: UsageSnapshot?,
        providers: List<UsageProviderSnapshot> = emptyList(),
    ): List<TopQuotaItem> {
        val glmProvider = providers.firstOrNull { it.id.equals("glm", ignoreCase = true) }
        return topQuotaGroups(usage, providers).map { group ->
            if (!group.id.equals("glm", ignoreCase = true)) {
                TopQuotaItem(group)
            } else {
                val details = glmDetails(glmProvider)
                TopQuotaItem(
                    group = group,
                    statusText = details.healthText.takeUnless { details.health == GLMHealth.AVAILABLE },
                    statusTone = details.health.tone,
                )
            }
        }
    }

    fun glmDetails(provider: UsageProviderSnapshot?): GLMQuotaDetails {
        val status = provider?.status.orEmpty().lowercase()
        val health = when {
            provider == null -> GLMHealth.UNCONFIGURED
            status == "available" -> GLMHealth.AVAILABLE
            status == "quota_exhausted" -> GLMHealth.EXHAUSTED
            status == "plan_expired" -> GLMHealth.PLAN_EXPIRED
            status.startsWith("stale_") -> GLMHealth.STALE
            status.startsWith("auth_") -> GLMHealth.AUTHENTICATION_FAILED
            else -> GLMHealth.UNAVAILABLE
        }
        val groups = provider?.quotaGroups.orEmpty()
        val windows = if (health.showsTrustedWindows) {
            groups.flatMap { it.windows }
                .filter { it.remainingPercentage.isFinite() }
                .sortedBy { it.windowMinutes }
                .take(2)
                .map { window -> glmWindow(window, health == GLMHealth.EXHAUSTED) }
        } else {
            emptyList()
        }
        val groupCapturedAt = groups.firstNotNullOfOrNull { it.capturedAt }
        val lastSuccessfulAt = groupCapturedAt
            ?: provider?.capturedAt?.takeIf { health.providerTimestampCanBeSuccess }
        return GLMQuotaDetails(
            planLabel = provider?.planName?.takeIf(String::isNotBlank)
                ?: "GLM Coding Plan",
            planLevelRaw = provider?.planLevel?.takeIf(String::isNotBlank),
            health = health,
            healthText = health.text,
            message = health.message(status),
            lastSuccessfulAt = lastSuccessfulAt,
            lastUpdatedAt = provider?.capturedAt,
            windows = windows,
        )
    }

    private fun glmWindow(
        window: com.agentgrid.mobile.domain.UsageWindow,
        explicitlyExhausted: Boolean,
    ): GLMWindowPresentation {
        val remaining = window.remainingPercentage.roundToInt().coerceIn(0, 100)
        val level = when {
            explicitlyExhausted && remaining == 0 -> QuotaLevel.EXHAUSTED
            remaining < 10 -> QuotaLevel.CRITICAL
            remaining < 20 -> QuotaLevel.LOW
            else -> QuotaLevel.NORMAL
        }
        val label = when {
            window.key.equals("5-hour", ignoreCase = true) || window.windowMinutes == 300 ->
                "5 小时"
            window.key.equals("weekly", ignoreCase = true) || window.windowMinutes == 10_080 ->
                "每周"
            else -> window.label
        }
        return GLMWindowPresentation(
            label = label,
            remainingPercentage = remaining,
            resetText = resetText(window.resetsAt),
            level = level,
            levelText = level.text,
            accessibilityText = "$label${"剩余 $remaining%"}，${level.text}",
        )
    }

    private data class QuotaPresentation(
        val title: String,
        val accent: QuotaAccent,
    )

    private enum class QuotaKind(
        val fixedTitle: String?,
        val accent: QuotaAccent,
    ) {
        GENERAL("GENERAL", QuotaAccent.MUTED),
        SPARK("SPARK", QuotaAccent.VIOLET),
        GLM("GLM", QuotaAccent.CYAN),
        OTHER(null, QuotaAccent.MUTED),
    }

    private fun quotaPresentation(group: QuotaGroup): QuotaPresentation {
        val kind = quotaKind(group)
        return QuotaPresentation(
            title = kind.fixedTitle
                ?: group.name?.takeIf(String::isNotBlank)?.uppercase()
                ?: group.id.uppercase(),
            accent = kind.accent,
        )
    }

    private fun quotaKind(group: QuotaGroup): QuotaKind = when {
        group.id.equals("glm", ignoreCase = true) -> QuotaKind.GLM
        isSparkQuota(group) -> QuotaKind.SPARK
        isGeneralQuota(group) -> QuotaKind.GENERAL
        else -> QuotaKind.OTHER
    }

    private fun isGeneralQuota(group: QuotaGroup): Boolean =
        group.id.equals("codex", ignoreCase = true)

    private fun isSparkQuota(group: QuotaGroup): Boolean =
        listOf(group.id, group.name.orEmpty()).any { value ->
            value.contains("spark", ignoreCase = true) ||
                value.contains("bengalfox", ignoreCase = true)
        }

    fun pointsForRange(
        points: List<DailyUsagePoint>,
        range: UsageRange,
    ): List<DailyUsagePoint> = points.takeLast(range.days)

    fun totalTokens(points: List<DailyUsagePoint>): Long =
        points.sumOf { it.totalTokens }

    fun totalEstimatedCostUSD(points: List<DailyUsagePoint>): Double? {
        val costs = points.mapNotNull { it.estimatedCostUSD }
        return costs.takeIf { it.isNotEmpty() }?.sum()
    }

    fun compactTokens(value: Long): String = when {
        value >= 1_000_000_000 -> decimal(value / 1_000_000_000.0) + "B"
        value >= 1_000_000 -> decimal(value / 1_000_000.0) + "M"
        value >= 1_000 -> decimal(value / 1_000.0) + "K"
        else -> value.coerceAtLeast(0).toString()
    }

    fun estimatedCostUSD(value: Double?): String {
        value ?: return "--"
        val safeValue = value.coerceAtLeast(0.0)
        return when {
            safeValue >= 1_000 -> "$" + decimal(safeValue / 1_000) + "K"
            safeValue >= 100 -> String.format(
                java.util.Locale.US,
                "$%.0f",
                safeValue,
            )
            safeValue >= 10 -> String.format(
                java.util.Locale.US,
                "$%.1f",
                safeValue,
            )
            else -> String.format(
                java.util.Locale.US,
                "$%.2f",
                safeValue,
            )
        }
    }

    fun resetText(
        resetsAt: Long?,
        now: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): String {
        resetsAt ?: return "重置时间未知"
        val remaining = resetsAt - now
        if (remaining <= 0) return "即将重置"

        val minutes = ceil(remaining / 60_000.0).toLong().coerceAtLeast(1)
        if (minutes < 60) return "${minutes} 分后重置"

        val hours = minutes / 60
        val restMinutes = minutes % 60
        if (hours < 24) {
            return if (restMinutes == 0L) {
                "${hours} 小时后重置"
            } else {
                "${hours} 小时 ${restMinutes} 分后重置"
            }
        }

        val formatter = DateTimeFormatter.ofPattern("MM月dd日 HH:mm")
        return formatter.format(
            Instant.ofEpochMilli(resetsAt).atZone(zoneId),
        ) + " 重置"
    }

    fun freshnessText(
        capturedAt: Long?,
        now: Long = System.currentTimeMillis(),
    ): String = capturedAt?.let { freshnessAgeText(it, now) + "更新" }
        ?: "等待用量数据"

    fun quotaFreshnessText(
        usage: UsageSnapshot?,
        now: Long = System.currentTimeMillis(),
    ): String {
        usage ?: return freshnessText(null, now)
        if (usage.quotaGroups.isEmpty()) {
            return freshnessText(usage.capturedAt, now)
        }
        return topQuotaGroups(usage).joinToString(separator = " · ") { group ->
            val age = group.capturedAt?.let { freshnessAgeText(it, now) }
                ?: "时间未知"
            "${quotaTitle(group)} $age"
        }
    }

    private fun freshnessAgeText(
        capturedAt: Long,
        now: Long,
    ): String {
        val elapsedMinutes = ((now - capturedAt).coerceAtLeast(0) / 60_000)
        return when {
            elapsedMinutes < 1 -> "刚刚"
            elapsedMinutes < 60 -> "${elapsedMinutes} 分钟前"
            elapsedMinutes < 24 * 60 -> "${elapsedMinutes / 60} 小时前"
            else -> "${elapsedMinutes / (24 * 60)} 天前"
        }
    }

    fun dateLabel(date: String): String {
        val parts = date.split("-")
        if (parts.size != 3) return date
        return "${parts[1]}/${parts[2]}"
    }

    private fun decimal(value: Double): String {
        val rounded = kotlin.math.round(value * 10) / 10
        return if (rounded % 1.0 == 0.0) {
            rounded.toLong().toString()
        } else {
            String.format(java.util.Locale.US, "%.1f", rounded)
        }
    }
}

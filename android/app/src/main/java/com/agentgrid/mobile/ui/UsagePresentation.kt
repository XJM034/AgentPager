package com.agentgrid.mobile.ui

import com.agentgrid.mobile.domain.DailyUsagePoint
import com.agentgrid.mobile.domain.QuotaGroup
import com.agentgrid.mobile.domain.UsageSnapshot
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.ceil

internal enum class UsageRange(
    val days: Int,
    val label: String,
) {
    SEVEN_DAYS(7, "7 天"),
    THIRTY_DAYS(30, "30 天"),
    NINETY_DAYS(90, "90 天"),
}

internal object UsagePresentation {
    fun topQuotaGroups(usage: UsageSnapshot?): List<QuotaGroup> {
        usage ?: return emptyList()
        val groups = usage.quotaGroups.ifEmpty {
            if (usage.windows.isEmpty()) {
                emptyList()
            } else {
                listOf(
                    QuotaGroup(
                        id = usage.limitID ?: "default",
                        name = usage.limitName,
                        capturedAt = usage.capturedAt,
                        windows = usage.windows,
                    ),
                )
            }
        }
        val general = groups.firstOrNull(::isGeneralQuota)
        val spark = groups.firstOrNull(::isSparkQuota)
        return listOfNotNull(general, spark).ifEmpty { groups.take(2) }
    }

    fun quotaTitle(group: QuotaGroup): String = when {
        isSparkQuota(group) -> "SPARK"
        isGeneralQuota(group) -> "GENERAL"
        !group.name.isNullOrBlank() -> group.name.uppercase()
        else -> group.id.uppercase()
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

package com.agentgrid.mobile.ui

import com.agentgrid.mobile.domain.DailyUsagePoint
import com.agentgrid.mobile.domain.QuotaGroup
import com.agentgrid.mobile.domain.UsageSnapshot
import com.agentgrid.mobile.domain.UsageProviderSnapshot
import com.agentgrid.mobile.domain.UsageWindow
import java.time.Instant
import java.time.ZoneId
import org.junit.Assert.assertEquals
import org.junit.Test

class UsagePresentationTest {
    @Test
    fun `顶部额度固定按通用和 Spark 分组且兼容旧快照`() {
        val general = QuotaGroup(
            id = "codex",
            windows = listOf(window("7d", 10_080)),
        )
        val spark = QuotaGroup(
            id = "codex_bengalfox",
            name = "GPT-5.3-Codex-Spark",
            windows = listOf(window("5h", 300), window("7d", 10_080)),
        )

        val groups = UsagePresentation.topQuotaGroups(
            UsageSnapshot(quotaGroups = listOf(spark, general)),
        )

        assertEquals(listOf("GENERAL", "SPARK"), groups.map(UsagePresentation::quotaTitle))
        assertEquals(listOf("7d"), groups[0].windows.map { it.label })
        assertEquals(listOf("5h", "7d"), groups[1].windows.map { it.label })

        val legacy = UsagePresentation.topQuotaGroups(
            UsageSnapshot(
                limitID = "codex",
                windows = listOf(window("7d", 10_080)),
            ),
        )
        assertEquals(listOf("GENERAL"), legacy.map(UsagePresentation::quotaTitle))
    }

    @Test
    fun `顶部额度固定为 General Spark GLM 且缺失 GLM 不占位`() {
        val general = QuotaGroup(
            id = "codex",
            windows = listOf(window("5H", 300)),
        )
        val spark = QuotaGroup(
            id = "codex_bengalfox",
            name = "GPT-5.3-Codex-Spark",
            windows = listOf(window("5H", 300)),
        )
        val glm = UsageProviderSnapshot(
            id = "glm",
            displayName = "GLM",
            planName = "GLM Coding Plan",
            quotaGroups = listOf(
                QuotaGroup(
                    id = "credit",
                    windows = listOf(window("5H", 300), window("WEEK", 10_080)),
                ),
            ),
        )

        val all = UsagePresentation.topQuotaGroups(
            usage = UsageSnapshot(quotaGroups = listOf(spark, general)),
            providers = listOf(glm),
        )
        val onlyGLM = UsagePresentation.topQuotaGroups(
            usage = null,
            providers = listOf(glm),
        )
        val withoutGLM = UsagePresentation.topQuotaGroups(
            usage = UsageSnapshot(quotaGroups = listOf(spark, general)),
            providers = emptyList(),
        )

        assertEquals(
            listOf("GENERAL", "SPARK", "GLM"),
            all.map(UsagePresentation::quotaTitle),
        )
        assertEquals(listOf("GLM"), onlyGLM.map(UsagePresentation::quotaTitle))
        assertEquals(
            listOf("GENERAL", "SPARK"),
            withoutGLM.map(UsagePresentation::quotaTitle),
        )
    }

    @Test
    fun `额度更新时间分别反映 General 和 Spark 新旧程度`() {
        val now = Instant.parse("2026-08-27T14:00:00Z").toEpochMilli()
        val general = QuotaGroup(
            id = "codex",
            capturedAt = now - 30_000,
            windows = listOf(window("7d", 10_080)),
        )
        val spark = QuotaGroup(
            id = "codex_bengalfox",
            name = "GPT-5.3-Codex-Spark",
            capturedAt = now - 2 * 60 * 60_000,
            windows = listOf(window("5h", 300), window("7d", 10_080)),
        )

        assertEquals(
            "GENERAL 刚刚 · SPARK 2 小时前",
            UsagePresentation.quotaFreshnessText(
                UsageSnapshot(
                    capturedAt = now - 30_000,
                    quotaGroups = listOf(general, spark),
                ),
                now = now,
            ),
        )
        assertEquals(
            "刚刚更新",
            UsagePresentation.quotaFreshnessText(
                UsageSnapshot(
                    capturedAt = now - 30_000,
                    limitID = "codex",
                    windows = listOf(window("7d", 10_080)),
                ),
                now = now,
            ),
        )
    }

    @Test
    fun `时间段切换只保留所选天数`() {
        val points = (1..90).map { index ->
            DailyUsagePoint(
                date = "2026-07-${index.toString().padStart(2, '0')}",
                totalTokens = index.toLong(),
            )
        }

        val sevenDays = UsagePresentation.pointsForRange(
            points,
            UsageRange.SEVEN_DAYS,
        )
        val thirtyDays = UsagePresentation.pointsForRange(
            points,
            UsageRange.THIRTY_DAYS,
        )

        assertEquals(7, sevenDays.size)
        assertEquals(84L, sevenDays.first().totalTokens)
        assertEquals(30, thirtyDays.size)
        assertEquals(61L, thirtyDays.first().totalTokens)
    }

    @Test
    fun `Token 汇总使用长整型并按量级压缩`() {
        val points = listOf(
            DailyUsagePoint(date = "2026-07-25", totalTokens = 900_000_000),
            DailyUsagePoint(date = "2026-07-26", totalTokens = 600_000_000),
        )

        val total = UsagePresentation.totalTokens(points)

        assertEquals(1_500_000_000L, total)
        assertEquals("1.5B", UsagePresentation.compactTokens(total))
    }

    @Test
    fun `美元预估只汇总有价格的数据并按量级显示`() {
        val points = listOf(
            DailyUsagePoint(
                date = "2026-07-25",
                estimatedCostUSD = 120.2,
            ),
            DailyUsagePoint(
                date = "2026-07-26",
                estimatedCostUSD = 271.7,
            ),
        )

        val total = UsagePresentation.totalEstimatedCostUSD(points)

        assertEquals(391.9, total!!, 0.0001)
        assertEquals("$392", UsagePresentation.estimatedCostUSD(total))
        assertEquals("$1.2K", UsagePresentation.estimatedCostUSD(1_249.0))
        assertEquals(
            null,
            UsagePresentation.totalEstimatedCostUSD(
                listOf(DailyUsagePoint(date = "2026-07-26")),
            ),
        )
    }

    @Test
    fun `额度重置同时支持倒计时和具体日期`() {
        val now = Instant.parse("2026-07-26T12:00:00Z").toEpochMilli()

        assertEquals(
            "2 小时 15 分后重置",
            UsagePresentation.resetText(
                resetsAt = now + (2 * 60 + 15) * 60_000L,
                now = now,
                zoneId = ZoneId.of("UTC"),
            ),
        )
        assertEquals(
            "07月29日 12:00 重置",
            UsagePresentation.resetText(
                resetsAt = now + 3 * 24 * 60 * 60_000L,
                now = now,
                zoneId = ZoneId.of("UTC"),
            ),
        )
    }

    private fun window(label: String, minutes: Int) = UsageWindow(
        key = "primary",
        label = label,
        usedPercentage = 8.0,
        remainingPercentage = 92.0,
        windowMinutes = minutes,
    )
}

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

    @Test
    fun `额度详情默认保持 Codex 且固定提供 GLM 切换`() {
        assertEquals(QuotaProviderTab.CODEX, UsagePresentation.defaultQuotaTab)
        assertEquals(
            listOf(QuotaProviderTab.CODEX, QuotaProviderTab.GLM),
            UsagePresentation.quotaProviderTabs,
        )
    }

    @Test
    fun `GLM 正常详情显示套餐原值双窗口和更新时间`() {
        val updatedAt = Instant.parse("2026-08-29T08:00:00Z").toEpochMilli()
        val provider = glmProvider(
            status = "available",
            capturedAt = updatedAt,
            planLevel = "lite",
            remaining = listOf(82.0, 64.0),
        )

        val details = UsagePresentation.glmDetails(provider)

        assertEquals(GLMHealth.AVAILABLE, details.health)
        assertEquals("可用", details.healthText)
        assertEquals("GLM Coding Plan", details.planLabel)
        assertEquals("lite", details.planLevelRaw)
        assertEquals(listOf("5 小时", "每周"), details.windows.map { it.label })
        assertEquals(listOf(82, 64), details.windows.map { it.remainingPercentage })
        assertEquals(updatedAt, details.lastSuccessfulAt)
        assertEquals(updatedAt, details.lastUpdatedAt)
    }

    @Test
    fun `GLM 低额度同时提供颜色等级和文字语义`() {
        val details = UsagePresentation.glmDetails(
            glmProvider(status = "available", remaining = listOf(19.0, 9.0)),
        )

        assertEquals(listOf(QuotaLevel.LOW, QuotaLevel.CRITICAL), details.windows.map { it.level })
        assertEquals(listOf("额度偏低", "额度告急"), details.windows.map { it.levelText })
        assertEquals(
            listOf("5 小时剩余 19%，额度偏低", "每周剩余 9%，额度告急"),
            details.windows.map { it.accessibilityText },
        )
    }

    @Test
    fun `只有明确耗尽状态才显示额度耗尽`() {
        val explicit = UsagePresentation.glmDetails(
            glmProvider(status = "quota_exhausted", remaining = listOf(0.0, 35.0)),
        )
        val ambiguous = UsagePresentation.glmDetails(
            glmProvider(status = "available", remaining = listOf(0.0, 35.0)),
        )

        assertEquals(GLMHealth.EXHAUSTED, explicit.health)
        assertEquals("额度耗尽", explicit.windows.first().levelText)
        assertEquals("额度告急", ambiguous.windows.first().levelText)
    }

    @Test
    fun `首次明确耗尽只记录更新时间不伪造最后成功时间`() {
        val updatedAt = Instant.parse("2026-08-29T08:00:00Z").toEpochMilli()
        val details = UsagePresentation.glmDetails(
            glmProvider(
                status = "quota_exhausted",
                capturedAt = updatedAt,
                remaining = emptyList(),
            ),
        )

        assertEquals(GLMHealth.EXHAUSTED, details.health)
        assertEquals(null, details.lastSuccessfulAt)
        assertEquals(updatedAt, details.lastUpdatedAt)
        assertEquals(emptyList<GLMWindowPresentation>(), details.windows)
    }

    @Test
    fun `GLM 陈旧数据保留最后可信窗口并区分最后成功和更新`() {
        val successfulAt = Instant.parse("2026-08-29T07:00:00Z").toEpochMilli()
        val updatedAt = Instant.parse("2026-08-29T08:00:00Z").toEpochMilli()
        val provider = glmProvider(
            status = "stale_timeout",
            capturedAt = updatedAt,
            groupCapturedAt = successfulAt,
            remaining = listOf(70.0, 55.0),
        )

        val details = UsagePresentation.glmDetails(provider)

        assertEquals(GLMHealth.STALE, details.health)
        assertEquals("数据陈旧", details.healthText)
        assertEquals(successfulAt, details.lastSuccessfulAt)
        assertEquals(updatedAt, details.lastUpdatedAt)
        assertEquals(listOf(70, 55), details.windows.map { it.remainingPercentage })
    }

    @Test
    fun `GLM 未启用鉴权失效和未知 Schema 不伪装成零额度`() {
        val unconfigured = UsagePresentation.glmDetails(null)
        val unauthorized = UsagePresentation.glmDetails(
            glmProvider(status = "auth_unauthorized", remaining = emptyList()),
        )
        val unknown = UsagePresentation.glmDetails(
            glmProvider(status = "unknown_schema", remaining = emptyList()),
        )

        assertEquals(GLMHealth.UNCONFIGURED, unconfigured.health)
        assertEquals("未启用", unconfigured.healthText)
        assertEquals("GLM Coding Plan", unconfigured.planLabel)
        assertEquals(emptyList<GLMWindowPresentation>(), unconfigured.windows)
        assertEquals("可选连接，不影响 ZCode 会话与手机审批", unconfigured.message)
        assertEquals(GLMHealth.AUTHENTICATION_FAILED, unauthorized.health)
        assertEquals("鉴权失效", unauthorized.healthText)
        assertEquals(emptyList<GLMWindowPresentation>(), unauthorized.windows)
        assertEquals(GLMHealth.UNAVAILABLE, unknown.health)
        assertEquals("暂不可用", unknown.healthText)
        assertEquals(emptyList<GLMWindowPresentation>(), unknown.windows)
    }

    @Test
    fun `GLM 首次临时服务错误显示暂不可用且不伪造额度`() {
        val unavailable = UsagePresentation.glmDetails(
            glmProvider(status = "server_error", remaining = emptyList()),
        )

        assertEquals(GLMHealth.UNAVAILABLE, unavailable.health)
        assertEquals("暂不可用", unavailable.healthText)
        assertEquals("上游服务暂不可用", unavailable.message)
        assertEquals(emptyList<GLMWindowPresentation>(), unavailable.windows)
    }

    @Test
    fun `顶部 GLM 最后可信读数明确标记异常状态`() {
        val stale = glmProvider(
            status = "stale_timeout",
            remaining = listOf(70.0, 55.0),
        )
        val unauthorized = glmProvider(
            status = "auth_unauthorized",
            remaining = listOf(70.0, 55.0),
        )

        assertEquals(
            "数据陈旧",
            UsagePresentation.topQuotaItems(null, listOf(stale)).single().statusText,
        )
        assertEquals(
            "鉴权失效",
            UsagePresentation.topQuotaItems(null, listOf(unauthorized)).single().statusText,
        )
    }

    private fun window(label: String, minutes: Int) = UsageWindow(
        key = "primary",
        label = label,
        usedPercentage = 8.0,
        remainingPercentage = 92.0,
        windowMinutes = minutes,
    )

    private fun glmProvider(
        status: String,
        capturedAt: Long = 1_787_900_200_000,
        groupCapturedAt: Long = capturedAt,
        planLevel: String? = null,
        remaining: List<Double>,
    ) = UsageProviderSnapshot(
        id = "glm",
        displayName = "GLM",
        planName = "GLM Coding Plan",
        planLevel = planLevel,
        capturedAt = capturedAt,
        status = status,
        quotaGroups = if (remaining.isEmpty()) {
            emptyList()
        } else {
            listOf(
                QuotaGroup(
                    id = "credit",
                    capturedAt = groupCapturedAt,
                    windows = remaining.mapIndexed { index, value ->
                        UsageWindow(
                            key = if (index == 0) "5-hour" else "weekly",
                            label = if (index == 0) "5H" else "WEEK",
                            usedPercentage = 100 - value,
                            remainingPercentage = value,
                            windowMinutes = if (index == 0) 300 else 10_080,
                            resetsAt = capturedAt + (index + 1) * 3_600_000,
                            remainingAmount = value * 10,
                        )
                    },
                ),
            )
        },
    )
}

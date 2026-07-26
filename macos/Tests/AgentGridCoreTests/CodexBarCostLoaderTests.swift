import Foundation
import Testing
@testable import AgentGridCore

@Test("CodexBar 成本数据转换为每日用量")
func codexBarCostDataParsesDailyUsage() throws {
    let data = Data(
        """
        [
          {
            "provider": "codex",
            "daily": [
              {
                "date": "2026-07-26",
                "inputTokens": 588000000,
                "outputTokens": 168726,
                "cacheReadTokens": 540000000,
                "totalTokens": 588168726,
                "totalCost": 424.043621,
                "modelsUsed": ["gpt-5.6-sol"],
                "modelBreakdowns": []
              }
            ]
          }
        ]
        """.utf8
    )

    let points = try #require(CodexBarCostLoader.parse(data))

    #expect(points.count == 1)
    #expect(points[0].date == "2026-07-26")
    #expect(points[0].cachedInputTokens == 540_000_000)
    #expect(points[0].totalTokens == 588_168_726)
    #expect(points[0].estimatedCostUSD == 424.043621)
}

@Test("CodexBar 非 Codex 数据不会被误用")
func codexBarCostDataRejectsOtherProviders() {
    let data = Data(
        """
        [{"provider":"claude","daily":[]}]
        """.utf8
    )

    #expect(CodexBarCostLoader.parse(data) == nil)
}

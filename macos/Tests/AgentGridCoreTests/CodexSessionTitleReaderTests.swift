import Foundation
import Testing
@testable import AgentGridCore

@Test("读取 Codex 总结标题并忽略无效记录")
func readsCodexSessionTitles() {
    let data = Data(
        """
        {"id":"session-1","thread_name":"优化手机任务标题","updated_at":"2026-07-26T01:00:00Z"}
        {"id":"session-2","thread_name":"   ","updated_at":"2026-07-26T01:00:00Z"}
        不是 JSON
        """.utf8
    )

    let titles = CodexSessionTitleReader.titles(from: data)

    #expect(titles == ["session-1": "优化手机任务标题"])
}

@Test("同一会话优先使用最新的 Codex 标题")
func latestCodexSessionTitleWins() {
    let data = Data(
        """
        {"id":"session-1","thread_name":"旧标题","updated_at":"2026-07-26T01:00:00Z"}
        {"id":"session-1","thread_name":"新的总结标题","updated_at":"2026-07-26T02:00:00Z"}
        """.utf8
    )

    let titles = CodexSessionTitleReader.titles(from: data)

    #expect(titles["session-1"] == "新的总结标题")
}

@Test("标题同步后不再刷新，出现新任务时恢复刷新")
func synchronizedTitleStopsRefreshingUntilNewTaskAppears() {
    let firstTask = TaskSnapshot(
        id: "session-1",
        source: .codexDesktop,
        projectName: "AgentGrid",
        title: "AgentGrid · 修改标题",
        lifecycle: .running
    )
    var store = TaskStore(tasks: [firstTask])
    var synchronizer = CodexSessionTitleSynchronizer()

    #expect(synchronizer.needsRefresh(for: store.tasks))

    let changed = synchronizer.applyAvailableTitles(
        ["session-1": "同步后的总结标题"],
        to: &store
    )

    #expect(changed)
    #expect(!synchronizer.needsRefresh(for: store.tasks))

    let secondTask = TaskSnapshot(
        id: "session-2",
        source: .codexCLI,
        projectName: "新任务",
        lifecycle: .running
    )
    store.upsert(secondTask)

    #expect(synchronizer.needsRefresh(for: store.tasks))
}

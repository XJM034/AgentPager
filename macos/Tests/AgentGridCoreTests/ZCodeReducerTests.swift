import Foundation
import Testing
@testable import AgentGridCore

@Test("ZCode 核心事件归约为启动、运行、工具活动与非终态空闲")
func zcodeCoreEventsReduceToConservativeLifecycle() {
    let startedAt = Date(timeIntervalSince1970: 1_000)
    var task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "SessionStart",
            cwd: "/private/work/AgentPager"
        ),
        existing: nil,
        now: startedAt
    )
    #expect(task.source == .zcode)
    #expect(task.projectName == "AgentPager")
    #expect(task.lifecycle == .starting)
    #expect(task.activity == .thinking)

    task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "UserPromptSubmit",
            cwd: "/private/work/AgentPager",
            prompt: "请修复 /Users/example/SecretProject/App.swift，token=sk-private-value"
        ),
        existing: task,
        now: startedAt.addingTimeInterval(1)
    )
    #expect(task.lifecycle == .running)
    #expect(task.activity == .thinking)
    #expect(task.userPrompt == nil)
    #expect(task.title.hasPrefix("AgentPager · "))
    #expect(!task.title.contains("/Users/example"))
    #expect(!task.title.contains("sk-private-value"))

    task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "PreToolUse",
            cwd: "/private/work/AgentPager",
            toolName: "Bash",
            toolInput: .object([
                "command": .string("cat /Users/example/SecretProject/App.swift"),
            ]),
            toolUseID: "tool-1"
        ),
        existing: task,
        now: startedAt.addingTimeInterval(2)
    )
    #expect(task.lifecycle == .running)
    #expect(task.activity == .executing)
    #expect(task.latestStep == "执行工具")

    task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "PostToolUse",
            cwd: "/private/work/AgentPager",
            toolName: "Bash",
            toolUseID: "tool-1"
        ),
        existing: task,
        now: startedAt.addingTimeInterval(3)
    )
    #expect(task.lifecycle == .running)
    #expect(task.activity == .thinking)

    let stoppedAt = startedAt.addingTimeInterval(4)
    task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "Stop",
            cwd: "/private/work/AgentPager"
        ),
        existing: task,
        now: stoppedAt
    )
    #expect(task.lifecycle == .idle)
    #expect(task.activity == nil)
    #expect(task.completedAt == nil)
    #expect(task.isUnread == false)
    #expect(!task.isTerminal)

    let firstTitle = task.title
    task = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "UserPromptSubmit",
            cwd: "/private/work/AgentPager",
            prompt: "开始下一轮，但保留首轮稳定标题"
        ),
        existing: task,
        now: stoppedAt.addingTimeInterval(1)
    )
    #expect(task.lifecycle == .running)
    #expect(task.activity == .thinking)
    #expect(task.title == firstTitle)
}

@Test("ZCode 核心工具复用现有活动语言且 Agent Task 只显示协作")
func zcodeToolsMapToExistingActivities() {
    let cases: [(String, AgentActivity, String)] = [
        ("Read", .reading, "读取文件"),
        ("Grep", .searching, "搜索内容"),
        ("Edit", .editing, "编辑文件"),
        ("Bash", .executing, "执行工具"),
        ("RunTests", .testing, "运行测试"),
        ("WebSearch", .browsing, "浏览内容"),
        ("Agent", .delegating, "协作任务"),
        ("Task", .delegating, "协作任务"),
    ]

    for (toolName, expectedActivity, expectedStep) in cases {
        let activity = ZCodeEventReducer.activity(for: toolName)
        #expect(activity == expectedActivity)
        #expect(ZCodeEventReducer.safeStep(for: activity) == expectedStep)
    }
}

@Test("未知 ZCode 事件不能改变已有生命周期")
func unknownZCodeEventPreservesLifecycle() {
    let running = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "UserPromptSubmit",
            cwd: "/private/work/AgentPager"
        ),
        existing: nil
    )
    let after = ZCodeEventReducer.task(
        from: ZCodeHookPayload(
            sessionID: "zcode-session-1",
            hookEventName: "FutureEvent",
            cwd: "/private/work/AgentPager"
        ),
        existing: running
    )

    #expect(after.lifecycle == .running)
    #expect(after.activity == .thinking)
}

@Test("ZCode 临时标题脱敏并限制长度")
func zcodeTitleIsSanitizedAndClipped() {
    let title = ZCodeEventReducer.safeTitle(
        projectName: "AgentPager",
        prompt: "token=sk-synthetic-value 请检查 /Users/example/private/Secret.swift 后继续补充一段很长的说明文字"
    )

    #expect(title.contains("[敏感信息]"))
    #expect(title.contains("[路径]"))
    #expect(!title.contains("sk-synthetic-value"))
    #expect(!title.contains("/Users/example"))
    #expect(title.count <= "AgentPager · ".count + 34)
}

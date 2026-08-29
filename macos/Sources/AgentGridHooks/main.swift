import AgentGridCore
import Foundation

@main
struct AgentPagerHooksCommand {
    static func main() {
        let source = resolveSource(from: CommandLine.arguments)
        let input = FileHandle.standardInput.readDataToEndOfFile()

        // 按来源解码载荷，仅用于判断事件类型以设置等待时长；
        // 解析失败时保持 fail-open，不能阻塞 Agent。
        let isPermission: Bool
        switch source {
        case .claude:
            let payload = try? JSONDecoder().decode(ClaudeHookPayload.self, from: input)
            isPermission = payload?.event == .permissionRequest
        case .codex:
            let payload = try? JSONDecoder().decode(CodexHookPayload.self, from: input)
            isPermission = payload?.hookEventName == .permissionRequest
        case .zcode:
            let payload = try? JSONDecoder().decode(ZCodeHookPayload.self, from: input)
            isPermission = payload?.event == .permissionRequest
        }

        // 权限请求可能等手机操作；ZCode 内部等待严格短于配置中的外层超时。
        // 其余事件最多等待 5 秒后放行。
        let timeoutMilliseconds = isPermission
            ? permissionTimeoutMilliseconds(for: source)
            : 5_000
        let response = HookBridgeClient.exchange(
            input: input,
            source: source,
            timeoutMilliseconds: timeoutMilliseconds
        )

        if !response.isEmpty {
            FileHandle.standardOutput.write(response)
        }
    }

    private static func permissionTimeoutMilliseconds(for source: HookSource) -> Int {
        switch source {
        case .claude: 86_400_000
        case .codex: 3_600_000
        case .zcode:
            ZCodePermissionTiming.clientResponseTimeoutMilliseconds
        }
    }

    private static func resolveSource(from arguments: [String]) -> HookSource {
        // 兼容 `--source claude` 与 `--source=claude` 两种写法。
        var iterator = arguments.dropFirst().makeIterator()
        while let argument = iterator.next() {
            if argument == "--source", let value = iterator.next() {
                return HookSource(rawValue: value) ?? .codex
            }
            if argument.hasPrefix("--source=") {
                let value = String(argument.dropFirst("--source=".count))
                return HookSource(rawValue: value) ?? .codex
            }
        }
        return .codex
    }
}

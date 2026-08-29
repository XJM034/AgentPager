import Foundation

/// 验证手机控制的签名、时钟与重放序号，并只产出已授权的领域控制。
/// Bridge 与自动化测试共用此接缝，避免测试绕过真实安全校验。
public struct SignedTaskControlAuthorizer: Sendable {
    private var replayGuard: ReplayGuard

    public init(replayGuard: ReplayGuard = ReplayGuard()) {
        self.replayGuard = replayGuard
    }

    public mutating func authorize(
        _ envelope: SignedControlEnvelope,
        secret: Data,
        now: Date = .now
    ) throws -> AuthorizedTaskControl {
        try replayGuard.validate(envelope, secret: secret, now: now)
        return AuthorizedTaskControl(
            requestID: envelope.messageId,
            taskID: envelope.payload.taskID,
            action: envelope.payload.action,
            value: envelope.payload.value,
            pendingRequestID: envelope.payload.pendingRequestID
        )
    }
}

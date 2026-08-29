import Foundation

public struct GLMHTTPResponse: Sendable {
    public var statusCode: Int
    public var data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol GLMNetworkClient: Sendable {
    func send(_ request: URLRequest) async throws -> GLMHTTPResponse
}

public struct URLSessionGLMNetworkClient: GLMNetworkClient {
    private let session: URLSession

    static var secureConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    public init(session: URLSession? = nil) {
        self.session = session ?? URLSession(configuration: Self.secureConfiguration)
    }

    public func send(_ request: URLRequest) async throws -> GLMHTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GLMQuotaError.invalidHTTPResponse
        }
        return GLMHTTPResponse(
            statusCode: httpResponse.statusCode,
            data: data
        )
    }
}

public enum GLMQuotaError: Error, Equatable, Sendable {
    case invalidHTTPResponse
    case invalidCredential
    case unavailable
    case invalidData
}

public protocol GLMQuotaFetching: Sendable {
    func fetchQuota(using key: String) async throws -> UsageProviderSnapshot
}

public struct GLMQuotaProvider: GLMQuotaFetching, Sendable {
    private static let endpoint = URL(
        string: "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
    )!

    private let network: any GLMNetworkClient
    private let now: @Sendable () -> Date

    public init(
        network: any GLMNetworkClient = URLSessionGLMNetworkClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.network = network
        self.now = now
    }

    public func fetchQuota(using key: String) async throws -> UsageProviderSnapshot {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "GET"
        request.setValue(key, forHTTPHeaderField: "Authorization")

        let response = try await network.send(request)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw GLMQuotaError.unavailable
        }

        let envelope: QuotaEnvelope
        do {
            envelope = try JSONDecoder().decode(QuotaEnvelope.self, from: response.data)
        } catch {
            throw GLMQuotaError.invalidData
        }
        guard envelope.success, envelope.code == 200, let data = envelope.data else {
            if envelope.code == 401 {
                throw GLMQuotaError.invalidCredential
            }
            throw GLMQuotaError.unavailable
        }

        let windows = try quotaWindows(from: data.limits)
        let capturedAt = now()
        return UsageProviderSnapshot(
            id: "glm",
            displayName: "GLM",
            planName: "GLM Coding Plan",
            planLevel: data.level?.value,
            capturedAt: capturedAt,
            status: "available",
            quotaGroups: [
                QuotaGroup(
                    id: "credit",
                    name: "CREDIT_LIMIT",
                    capturedAt: capturedAt,
                    windows: windows
                ),
            ]
        )
    }

    private func quotaWindows(from limits: [QuotaLimit]) throws -> [UsageWindow] {
        var matched: [WindowKind: UsageWindow] = [:]
        for limit in limits where limit.type == "CREDIT_LIMIT" {
            guard let kind = WindowKind(unit: limit.unit, number: limit.number) else {
                continue
            }
            guard let usedPercentage = limit.percentage?.value,
                  usedPercentage.isFinite,
                  (0 ... 100).contains(usedPercentage),
                  let remainingAmount = limit.remaining?.value,
                  remainingAmount.isFinite else {
                throw GLMQuotaError.invalidData
            }
            matched[kind] = UsageWindow(
                key: kind.key,
                label: kind.label,
                usedPercentage: usedPercentage,
                remainingPercentage: min(max(100 - usedPercentage, 0), 100),
                windowMinutes: kind.windowMinutes,
                resetsAt: date(milliseconds: limit.nextResetTime?.value),
                quotaType: limit.type,
                limitAmount: finiteValue(limit.usage?.value),
                usedAmount: finiteValue(limit.currentValue?.value),
                remainingAmount: remainingAmount
            )
        }

        guard let fiveHour = matched[.fiveHour],
              let weekly = matched[.weekly] else {
            throw GLMQuotaError.invalidData
        }
        return [fiveHour, weekly]
    }

    private func finiteValue(_ value: Double?) -> Double? {
        guard let value, value.isFinite else { return nil }
        return value
    }

    private func date(milliseconds: Double?) -> Date? {
        guard let milliseconds, milliseconds.isFinite else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }
}

private enum WindowKind: Hashable {
    case fiveHour
    case weekly

    init?(unit: Int?, number: Int?) {
        switch (unit, number) {
        case (3, 5): self = .fiveHour
        case (6, 1): self = .weekly
        default: return nil
        }
    }

    var key: String {
        switch self {
        case .fiveHour: "5-hour"
        case .weekly: "weekly"
        }
    }

    var label: String {
        switch self {
        case .fiveHour: "5H"
        case .weekly: "WEEK"
        }
    }

    var windowMinutes: Int {
        switch self {
        case .fiveHour: 300
        case .weekly: 10_080
        }
    }
}

private struct QuotaEnvelope: Decodable {
    var success: Bool
    var code: Int
    var data: QuotaData?
}

private struct QuotaData: Decodable {
    var level: LossyString?
    var limits: [QuotaLimit]
}

private struct QuotaLimit: Decodable {
    var type: String?
    var unit: Int?
    var number: Int?
    var usage: LossyDouble?
    var currentValue: LossyDouble?
    var remaining: LossyDouble?
    var percentage: LossyDouble?
    var nextResetTime: LossyDouble?
}

private struct LossyDouble: Decodable {
    var value: Double?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(Double.self)
    }
}

private struct LossyString: Decodable {
    var value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try? container.decode(String.self)
    }
}

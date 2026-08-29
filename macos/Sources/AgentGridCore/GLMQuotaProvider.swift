import Foundation
import CoreFoundation

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
    case unauthorized
    case forbidden
    case rateLimited
    case planExpired
    case quotaExhausted
    case timedOut
    case serverUnavailable
    case nonJSON
    case missingFields
    case unknownSchema
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

        let response: GLMHTTPResponse
        do {
            response = try await network.send(request)
        } catch let error as URLError where error.code == .timedOut {
            throw GLMQuotaError.timedOut
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw GLMQuotaError.unavailable
        }
        switch response.statusCode {
        case 200 ..< 300:
            break
        case 401:
            throw GLMQuotaError.unauthorized
        case 403:
            throw GLMQuotaError.forbidden
        case 429:
            throw GLMQuotaError.rateLimited
        case 500 ... 599:
            throw GLMQuotaError.serverUnavailable
        default:
            throw GLMQuotaError.unavailable
        }

        let root: [String: Any]
        do {
            let object = try JSONSerialization.jsonObject(with: response.data)
            guard let dictionary = object as? [String: Any] else {
                throw GLMQuotaError.unknownSchema
            }
            root = dictionary
        } catch let error as GLMQuotaError {
            throw error
        } catch {
            throw GLMQuotaError.nonJSON
        }

        let success = try requiredBool(root, key: "success")
        let code = try requiredInt(root, key: "code")
        guard success, code == 200 else {
            throw classifyBusinessFailure(code: code, reason: root["reason"])
        }
        guard let rawData = root["data"] else {
            throw GLMQuotaError.missingFields
        }
        guard let data = rawData as? [String: Any] else {
            throw GLMQuotaError.unknownSchema
        }

        let windows = try quotaWindows(from: data)
        let capturedAt = now()
        return UsageProviderSnapshot(
            id: "glm",
            displayName: "GLM",
            planName: "GLM Coding Plan",
            planLevel: try optionalString(data, key: "level"),
            capturedAt: capturedAt,
            status: windows.contains(where: isExplicitlyExhausted)
                ? "quota_exhausted"
                : "available",
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

    private func quotaWindows(from data: [String: Any]) throws -> [UsageWindow] {
        guard let rawLimits = data["limits"] else {
            throw GLMQuotaError.missingFields
        }
        guard let limits = rawLimits as? [Any] else {
            throw GLMQuotaError.unknownSchema
        }
        var matched: [WindowKind: UsageWindow] = [:]
        var sawCreditLimit = false
        for rawLimit in limits {
            guard let limit = rawLimit as? [String: Any] else {
                throw GLMQuotaError.unknownSchema
            }
            let type = try requiredString(limit, key: "type")
            guard type == "CREDIT_LIMIT" else { continue }
            sawCreditLimit = true
            let unit = try requiredInt(limit, key: "unit")
            let number = try requiredInt(limit, key: "number")
            guard let kind = WindowKind(unit: unit, number: number) else {
                continue
            }
            let descriptor = kind.descriptor
            let usedPercentage = try requiredDouble(limit, key: "percentage")
            let remainingAmount = try requiredDouble(limit, key: "remaining")
            guard (0 ... 100).contains(usedPercentage) else {
                throw GLMQuotaError.invalidData
            }
            matched[kind] = UsageWindow(
                key: descriptor.key,
                label: descriptor.label,
                usedPercentage: usedPercentage,
                remainingPercentage: min(max(100 - usedPercentage, 0), 100),
                windowMinutes: descriptor.windowMinutes,
                resetsAt: date(milliseconds: try optionalDouble(limit, key: "nextResetTime")),
                quotaType: type,
                limitAmount: try optionalDouble(limit, key: "usage"),
                usedAmount: try optionalDouble(limit, key: "currentValue"),
                remainingAmount: remainingAmount
            )
        }

        guard let fiveHour = matched[.fiveHour],
              let weekly = matched[.weekly] else {
            throw sawCreditLimit
                ? GLMQuotaError.missingFields
                : GLMQuotaError.unknownSchema
        }
        return [fiveHour, weekly]
    }

    private func classifyBusinessFailure(code: Int, reason: Any?) -> GLMQuotaError {
        switch code {
        case 401: return .unauthorized
        case 403: return .forbidden
        case 429: return .rateLimited
        case 1308, 1310: return .quotaExhausted
        case 1309: return .planExpired
        case 500 ... 599: return .serverUnavailable
        default: break
        }
        guard let reason = reason as? String else { return .unavailable }
        switch reason.uppercased() {
        case "PLAN_EXPIRED", "PACKAGE_EXPIRED": return .planExpired
        case "QUOTA_EXHAUSTED", "CREDIT_EXHAUSTED": return .quotaExhausted
        default: return .unavailable
        }
    }

    private func requiredBool(_ object: [String: Any], key: String) throws -> Bool {
        guard let raw = object[key] else { throw GLMQuotaError.missingFields }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            throw GLMQuotaError.unknownSchema
        }
        return number.boolValue
    }

    private func requiredString(_ object: [String: Any], key: String) throws -> String {
        guard let raw = object[key] else { throw GLMQuotaError.missingFields }
        guard let value = raw as? String else { throw GLMQuotaError.unknownSchema }
        return value
    }

    private func optionalString(_ object: [String: Any], key: String) throws -> String? {
        guard let raw = object[key], !(raw is NSNull) else { return nil }
        guard let value = raw as? String else { throw GLMQuotaError.unknownSchema }
        return value
    }

    private func requiredInt(_ object: [String: Any], key: String) throws -> Int {
        let value = try requiredDouble(object, key: key)
        guard value.rounded() == value else { throw GLMQuotaError.unknownSchema }
        return Int(value)
    }

    private func requiredDouble(_ object: [String: Any], key: String) throws -> Double {
        guard let raw = object[key], !(raw is NSNull) else {
            throw GLMQuotaError.missingFields
        }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw GLMQuotaError.unknownSchema
        }
        let value = number.doubleValue
        guard value.isFinite else { throw GLMQuotaError.invalidData }
        return value
    }

    private func optionalDouble(_ object: [String: Any], key: String) throws -> Double? {
        guard let raw = object[key], !(raw is NSNull) else { return nil }
        guard let number = raw as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            throw GLMQuotaError.unknownSchema
        }
        let value = number.doubleValue
        guard value.isFinite else { throw GLMQuotaError.invalidData }
        return value
    }

    private func isExplicitlyExhausted(_ window: UsageWindow) -> Bool {
        window.remainingPercentage == 0 && window.remainingAmount == 0
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

    var descriptor: WindowDescriptor {
        switch self {
        case .fiveHour:
            WindowDescriptor(key: "5-hour", label: "5H", windowMinutes: 300)
        case .weekly:
            WindowDescriptor(key: "weekly", label: "WEEK", windowMinutes: 10_080)
        }
    }
}

private struct WindowDescriptor {
    var key: String
    var label: String
    var windowMinutes: Int
}

import Foundation
import Testing
@testable import AgentGridCore

@Test("GLM 默认网络会话禁用 Cookie 与缓存")
func glmDefaultNetworkSessionDisablesCookiesAndCaching() {
    let configuration = URLSessionGLMNetworkClient.secureConfiguration

    #expect(!configuration.httpShouldSetCookies)
    #expect(configuration.httpCookieAcceptPolicy == .never)
    #expect(configuration.httpCookieStorage == nil)
    #expect(configuration.urlCache == nil)
    #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
}

@Test("GLM Gate 0 CREDIT_LIMIT 响应投影为 5 小时和每周可用额度")
func glmGateZeroResponseProjectsAvailableQuotaWindows() async throws {
    let response = """
    {
      "success": true,
      "code": 200,
      "data": {
        "level": "lite",
        "limits": [
          {
            "type": "CREDIT_LIMIT",
            "unit": 3,
            "number": 5,
            "usage": 2000,
            "currentValue": 102,
            "remaining": 1897,
            "percentage": 5,
            "nextResetTime": 1787904223581
          },
          {
            "type": "CREDIT_LIMIT",
            "unit": 6,
            "number": 1,
            "usage": 10000,
            "currentValue": 102,
            "remaining": 9897,
            "percentage": 1,
            "nextResetTime": 1788490685990
          }
        ]
      }
    }
    """
    let network = RecordingGLMNetworkClient(
        response: GLMHTTPResponse(
            statusCode: 200,
            data: Data(response.utf8)
        )
    )
    let capturedAt = Date(timeIntervalSince1970: 1_787_900_134)
    let provider = GLMQuotaProvider(
        network: network,
        now: { capturedAt }
    )

    let snapshot = try await provider.fetchQuota(using: "candidate-key")
    let group = try #require(snapshot.quotaGroups.single)

    #expect(snapshot.id == "glm")
    #expect(snapshot.displayName == "GLM")
    #expect(snapshot.planName == "GLM Coding Plan")
    #expect(snapshot.planLevel == "lite")
    #expect(snapshot.capturedAt == capturedAt)
    #expect(snapshot.status == "available")
    #expect(group.id == "credit")
    #expect(group.windows.map(\.key) == ["5-hour", "weekly"])
    #expect(group.windows.map(\.usedPercentage) == [5, 1])
    #expect(group.windows.map(\.remainingPercentage) == [95, 99])
    #expect(group.windows.map(\.remainingAmount) == [1897, 9897])
    #expect(group.windows.map(\.windowMinutes) == [300, 10_080])

    let request = try #require(await network.lastRequest)
    #expect(request.url?.absoluteString == "https://open.bigmodel.cn/api/monitor/usage/quota/limit")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "candidate-key")
}

@Test("GLM HTTP 200 仍拒绝业务层 401")
func glmRejectsBusinessUnauthorizedInsideHTTP200() async {
    let provider = GLMQuotaProvider(
        network: RecordingGLMNetworkClient(
            response: GLMHTTPResponse(
                statusCode: 200,
                data: Data(#"{"success":false,"code":401,"data":null,"msg":"redacted"}"#.utf8)
            )
        )
    )

    await #expect(throws: GLMQuotaError.invalidCredential) {
        try await provider.fetchQuota(using: "invalid-candidate")
    }
}

@Test("GLM level 缺失时保留通用套餐名且不猜测等级")
func glmFallsBackToGenericPlanNameWithoutLevel() async throws {
    let provider = GLMQuotaProvider(
        network: RecordingGLMNetworkClient(
            response: GLMHTTPResponse(
                statusCode: 200,
                data: validQuotaResponse(levelField: "")
            )
        )
    )

    let snapshot = try await provider.fetchQuota(using: "candidate")

    #expect(snapshot.planName == "GLM Coding Plan")
    #expect(snapshot.planLevel == nil)
}

@Test(arguments: ["null", #""unknown""#, "-1", "101"])
func glmRejectsMissingIllegalOrUnknownPercentage(_ percentage: String) async {
    let provider = GLMQuotaProvider(
        network: RecordingGLMNetworkClient(
            response: GLMHTTPResponse(
                statusCode: 200,
                data: validQuotaResponse(
                    levelField: #""level":"opaque","#,
                    fiveHourPercentage: percentage
                )
            )
        )
    )

    await #expect(throws: GLMQuotaError.invalidData) {
        try await provider.fetchQuota(using: "candidate")
    }
}

private func validQuotaResponse(
    levelField: String,
    fiveHourPercentage: String = "5"
) -> Data {
    Data(
        """
        {
          "success": true,
          "code": 200,
          "data": {
            \(levelField)
            "limits": [
              {
                "type": "CREDIT_LIMIT", "unit": 3, "number": 5,
                "usage": 2000, "currentValue": 102, "remaining": 1897,
                "percentage": \(fiveHourPercentage)
              },
              {
                "type": "CREDIT_LIMIT", "unit": 6, "number": 1,
                "usage": 10000, "currentValue": 102, "remaining": 9897,
                "percentage": 1
              }
            ]
          }
        }
        """.utf8
    )
}

private actor RecordingGLMNetworkClient: GLMNetworkClient {
    private(set) var lastRequest: URLRequest?
    private let response: GLMHTTPResponse

    init(response: GLMHTTPResponse) {
        self.response = response
    }

    func send(_ request: URLRequest) async throws -> GLMHTTPResponse {
        lastRequest = request
        return response
    }
}

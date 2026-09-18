import XCTest
@testable import AILSA_SS

final class UsageServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        let resetExpectation = expectation(description: "reset usage mock url protocol")
        Task {
            await UsageMockURLProtocol.store.reset()
            resetExpectation.fulfill()
        }
        wait(for: [resetExpectation], timeout: 1)
    }

    func testFetchUsageShowsDirectServerErrorMessageForExpiredToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = DefaultUsageService(
            session: session,
            configPath: URL(fileURLWithPath: "/tmp/nonexistent-config.toml")
        )

        await UsageMockURLProtocol.store.setHandler { request in
            let url = try XCTUnwrap(request.url?.absoluteString)
            if url.contains("/backend-api/wham/usage") {
                return (
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 401,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data(#"{"error":{"message":"Provided authentication token is expired. Please try signing in again.","code":"token_expired"}}"#.utf8)
                )
            }

            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 403,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data("<html>forbidden</html>".utf8)
            )
        }

        do {
            _ = try await service.fetchUsage(accessToken: "expired-token", accountID: "account-1")
            XCTFail("Expected usage request to fail")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "Provided authentication token is expired. Please try signing in again."
            )
        }
    }

    func testBackgroundNetworkSessionDisablesPersistentHTTPStorage() {
        let configuration = BackgroundNetworkSession.shared.configuration

        XCTAssertEqual(configuration.identifier, nil)
        XCTAssertEqual(configuration.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertNil(configuration.urlCache)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertFalse(configuration.httpShouldSetCookies)
    }

    func testWeekOnlyPayloadDoesNotInventFiveHourAndKeepsNamedAdditionalPool() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UsageMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = DefaultUsageService(
            session: session,
            configPath: URL(fileURLWithPath: "/tmp/nonexistent-config.toml")
        )
        await UsageMockURLProtocol.store.setHandler { request in
            let payload = """
            {
              "plan_type": "pro_20x",
              "rate_limit": {
                "primary_window": {
                  "used_percent": 42,
                  "limit_window_seconds": 604800,
                  "reset_at": 1800604800
                }
              },
              "additional_rate_limits": [
                {
                  "id": "spark",
                  "display_name": "Spark",
                  "rate_limit": {
                    "primary_window": {
                      "used_percent": 12,
                      "limit_window_seconds": 604800,
                      "reset_at": 1800604800
                    }
                  }
                }
              ]
            }
            """
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(payload.utf8)
            )
        }

        let usage = try await service.fetchUsage(accessToken: "test-token", accountID: "account-1")

        XCTAssertNil(usage.fiveHour)
        XCTAssertEqual(usage.oneWeek?.usedPercent, 42)
        XCTAssertEqual(usage.codexQuotaFamilies?.map(\.id), ["spark"])
        XCTAssertEqual(usage.codexQuotaFamilies?.first?.displayName, "Spark")
        XCTAssertEqual(usage.codexQuotaFamilies?.first?.buckets.first?.usedPercent, 12)
    }

    func testUsageDebugRequestSummaryIncludesRequestDetails() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://chatgpt.com/backend-api/wham/usage")))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("account-1", forHTTPHeaderField: "ChatGPT-Account-Id")
        request.setValue("codex-tools-swift/0.1", forHTTPHeaderField: "User-Agent")

        let summary = DefaultUsageService.debugRequestLogSummary(for: request)
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(summary.utf8)) as? NSDictionary
        )

        XCTAssertEqual(
            payload,
            [
                "method": "GET",
                "url": "https://chatgpt.com/backend-api/wham/usage",
                "headers": [
                    "Accept": "application/json",
                    "ChatGPT-Account-Id": "account-1",
                    "User-Agent": "codex-tools-swift/0.1"
                ]
            ] as NSDictionary
        )
    }

    func testUsageDebugResponseBodyReturnsRawJSONPayload() {
        let body = DefaultUsageService.debugResponseLogBody(
            for: Data(#"{"detail":{"code":"deactivated_workspace"}}"#.utf8)
        )

        XCTAssertEqual(body, #"{"detail":{"code":"deactivated_workspace"}}"#)
    }
}

private final class UsageMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = UsageMockURLProtocolStore()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Task {
            do {
                guard let handler = await Self.store.handler() else {
                    client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                    return
                }

                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {}
}

private actor UsageMockURLProtocolStore {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private var currentHandler: Handler?

    func setHandler(_ handler: @escaping Handler) {
        currentHandler = handler
    }

    func handler() -> Handler? {
        currentHandler
    }

    func reset() {
        currentHandler = nil
    }
}

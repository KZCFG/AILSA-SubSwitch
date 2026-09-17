import XCTest
@testable import Copool

final class WorkspaceMetadataServiceTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        WorkspaceMetadataMockURLProtocol.store.reset()
    }

    func testFetchWorkspaceMetadataUsesUsageTimeoutBudget() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkspaceMetadataMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = DefaultWorkspaceMetadataService(
            session: session,
            configPath: URL(fileURLWithPath: "/tmp/nonexistent-config.toml")
        )

        WorkspaceMetadataMockURLProtocol.store.setHandler { request in
            XCTAssertEqual(request.timeoutInterval, 18)
            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"{"items":[]}"#.utf8)
            )
        }

        let metadata = try await service.fetchWorkspaceMetadata(accessToken: "token-1")
        XCTAssertEqual(metadata, [])
    }

    func testWorkspaceMetadataPrefersConcreteServerErrorOverTimeoutFallback() {
        let message = DefaultWorkspaceMetadataService.debugPreferredUserFacingFailureMessage(
            from: [
                "https://chatgpt.com/backend-api/accounts -> The request timed out.",
                "https://chatgpt.com/backend-api/accounts -> 401: Provided authentication token is expired. Please try signing in again."
            ]
        )

        XCTAssertEqual(message, "Provided authentication token is expired. Please try signing in again.")
    }

    func testWorkspaceMetadataDebugRequestSummaryIncludesRequestDetails() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://chatgpt.com/backend-api/accounts")))
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-tools-swift/0.1", forHTTPHeaderField: "User-Agent")

        let summary = DefaultWorkspaceMetadataService.debugRequestLogSummary(for: request)
        let payload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(summary.utf8)) as? NSDictionary
        )

        XCTAssertEqual(
            payload,
            [
                "method": "GET",
                "url": "https://chatgpt.com/backend-api/accounts",
                "headers": [
                    "Accept": "application/json",
                    "User-Agent": "codex-tools-swift/0.1"
                ]
            ] as NSDictionary
        )
    }

    func testWorkspaceMetadataDebugResponseBodyReturnsRawJSONPayload() {
        let body = DefaultWorkspaceMetadataService.debugResponseLogBody(
            for: Data(#"{"items":[{"id":"account-1","name":"Workspace A","structure":"workspace"}]}"#.utf8)
        )

        XCTAssertEqual(
            body,
            #"{"items":[{"id":"account-1","name":"Workspace A","structure":"workspace"}]}"#
        )
    }

    func testFetchWorkspaceMetadataRetriesOnceAfterHTML403Forbidden() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WorkspaceMetadataMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let service = DefaultWorkspaceMetadataService(
            session: session,
            configPath: URL(fileURLWithPath: "/tmp/nonexistent-config.toml")
        )

        let requestCounter = WorkspaceMetadataRequestCounter()
        WorkspaceMetadataMockURLProtocol.store.setHandler { request in
            let requestCount = requestCounter.increment()

            if requestCount == 1 {
                return (
                    HTTPURLResponse(
                        url: try XCTUnwrap(request.url),
                        statusCode: 403,
                        httpVersion: nil,
                        headerFields: nil
                    )!,
                    Data(#"<html><head><meta name="viewport" content="width=device-width"></head><body>forbidden</body></html>"#.utf8)
                )
            }

            return (
                HTTPURLResponse(
                    url: try XCTUnwrap(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data(#"{"items":[{"id":"account-1","name":"Workspace A","structure":"workspace"}]}"#.utf8)
            )
        }

        let metadata = try await service.fetchWorkspaceMetadata(accessToken: "token-1")

        XCTAssertEqual(requestCounter.value, 2)
        XCTAssertEqual(
            metadata,
            [WorkspaceMetadata(accountID: "account-1", workspaceName: "Workspace A", structure: "workspace")]
        )
    }
}

private final class WorkspaceMetadataMockURLProtocol: URLProtocol, @unchecked Sendable {
    static let store = WorkspaceMetadataMockURLProtocolStore()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.store.handler() else {
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

    override func stopLoading() {}
}

private final class WorkspaceMetadataMockURLProtocolStore: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)

    private let lock = NSLock()
    private var currentHandler: Handler?

    func setHandler(_ handler: @escaping Handler) {
        lock.lock()
        currentHandler = handler
        lock.unlock()
    }

    func handler() -> Handler? {
        lock.lock()
        defer { lock.unlock() }
        return currentHandler
    }

    func reset() {
        lock.lock()
        currentHandler = nil
        lock.unlock()
    }
}

private final class WorkspaceMetadataRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

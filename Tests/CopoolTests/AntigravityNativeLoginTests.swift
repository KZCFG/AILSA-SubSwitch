import Foundation
import XCTest
@testable import Copool

final class AntigravityNativeLoginTests: XCTestCase {
    func testBrowserLoginPreflightsFirstEndpointThenMakesOneLogin() async throws {
        let recorder = NativeLoginRequestRecorder()
        let service = AntigravityNativeUsageService(
            processListing: nativeProcessListing,
            listeningPorts: { _ in [61_001, 61_002] },
            requestLoader: { request in
                await recorder.append(NativeLoginRequestRecord(request: request))
                switch request.url?.lastPathComponent {
                case "GetUnleashData":
                    // Reachability-only preflight: a native server may return
                    // an empty, non-JSON response here.
                    return (Data(), nativeHTTPResponse(for: request, statusCode: 200))
                case "Login":
                    return (
                        Data(#"{"authResult":{"hasValidAuth":true}}"#.utf8),
                        nativeHTTPResponse(for: request, statusCode: 200)
                    )
                default:
                    throw URLError(.badURL)
                }
            }
        )

        try await service.beginBrowserLogin(readinessTimeout: 1, responseTimeout: 120)

        let requests = await recorder.requests()
        XCTAssertEqual(requests.map(\.path), ["GetUnleashData", "Login"])
        XCTAssertEqual(requests.map(\.port), [61_001, 61_001])
        XCTAssertEqual(requests.filter { $0.path == "Login" }.count, 1)
        XCTAssertEqual(requests.last?.timeoutInterval, 120)

        let loginBody = try XCTUnwrap(requests.last?.body)
        let loginPayload = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: loginBody) as? [String: Any]
        )
        XCTAssertEqual(loginPayload.keys.sorted(), ["isGcpTos"])
        XCTAssertEqual(loginPayload["isGcpTos"] as? Bool, false)
    }

    func testBrowserLoginDoesNotRetryOAuthAfterLoginTimeout() async throws {
        let recorder = NativeLoginRequestRecorder()
        let service = AntigravityNativeUsageService(
            processListing: nativeProcessListing,
            listeningPorts: { _ in [61_011, 61_012] },
            requestLoader: { request in
                await recorder.append(NativeLoginRequestRecord(request: request))
                switch request.url?.lastPathComponent {
                case "GetUnleashData":
                    return (Data(), nativeHTTPResponse(for: request, statusCode: 200))
                case "Login":
                    throw URLError(.timedOut)
                default:
                    throw URLError(.badURL)
                }
            }
        )

        do {
            try await service.beginBrowserLogin(readinessTimeout: 1, responseTimeout: 120)
            XCTFail("Expected the native Login RPC to time out")
        } catch {
            // The failure must stop the attempt rather than probing another
            // endpoint and opening a second browser OAuth flow.
        }

        let requests = await recorder.requests()
        XCTAssertEqual(requests.map(\.path), ["GetUnleashData", "Login"])
        XCTAssertEqual(requests.map(\.port), [61_011, 61_011])
        XCTAssertEqual(requests.filter { $0.path == "Login" }.count, 1)
    }

    func testBrowserLoginRejectsFailedAuthResultWithoutRetrying() async throws {
        let recorder = NativeLoginRequestRecorder()
        let service = AntigravityNativeUsageService(
            processListing: nativeProcessListing,
            listeningPorts: { _ in [61_016, 61_017] },
            requestLoader: { request in
                await recorder.append(NativeLoginRequestRecord(request: request))
                switch request.url?.lastPathComponent {
                case "GetUnleashData":
                    return (Data(), nativeHTTPResponse(for: request, statusCode: 200))
                case "Login":
                    return (
                        Data(#"{"authResult":{"hasValidAuth":false}}"#.utf8),
                        nativeHTTPResponse(for: request, statusCode: 200)
                    )
                default:
                    throw URLError(.badURL)
                }
            }
        )

        do {
            try await service.beginBrowserLogin(readinessTimeout: 1, responseTimeout: 120)
            XCTFail("Expected a failed native auth result")
        } catch {
            // A failed auth result is terminal for this one browser-login call.
        }
        let requests = await recorder.requests()
        XCTAssertEqual(requests.map(\.path), ["GetUnleashData", "Login"])
        XCTAssertEqual(requests.map(\.port), [61_016, 61_016])
    }

    func testNativeUsageAllowsEmptyUnleashPreflightButStillDecodesStatusAndQuota() async throws {
        let recorder = NativeLoginRequestRecorder()
        let service = AntigravityNativeUsageService(
            processListing: nativeProcessListing,
            listeningPorts: { _ in [61_021] },
            requestLoader: { request in
                await recorder.append(NativeLoginRequestRecord(request: request))
                let data: Data
                switch request.url?.lastPathComponent {
                case "GetUnleashData":
                    data = Data()
                case "GetUserStatus":
                    data = Data(#"{"userStatus":{"email":"native@example.com","userTier":{"name":"Pro"}}}"#.utf8)
                case "RetrieveUserQuotaSummary":
                    data = Data(#"{"response":{"groups":[{"displayName":"Models","buckets":[{"bucketId":"pro","displayName":"Pro","remainingFraction":0.5,"window":"5h"}]}]}}"#.utf8)
                default:
                    throw URLError(.badURL)
                }
                return (data, nativeHTTPResponse(for: request, statusCode: 200))
            }
        )

        let usage = try await service.fetchCurrentUsage()
        let requests = await recorder.requests()

        XCTAssertEqual(usage.email, "native@example.com")
        XCTAssertEqual(usage.usage.quotaFamilies?.first?.buckets.first?.usedPercent, 50)
        XCTAssertEqual(
            requests.map(\.path),
            ["GetUnleashData", "GetUserStatus", "RetrieveUserQuotaSummary"]
        )
    }

    func testCurrentNativeUsageNormalizesLoopbackTransportFailure() async throws {
        let service = AntigravityUsageService(nativeUsageService: failingNativeUsageService())

        do {
            _ = try await service.fetchCurrentNativeUsage()
            XCTFail("Expected loopback transport failure")
        } catch let error as AppError {
            guard case .network = error else {
                return XCTFail("Expected a diagnostic-safe network error")
            }
        }
    }

    func testRemote403ReportsQuotaUnavailableRatherThanModelAvailability() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NativeLoginRemote403URLProtocol.self]
        let service = AntigravityUsageService(
            session: URLSession(configuration: configuration),
            nativeUsageService: failingNativeUsageService(),
            userInfoLoader: { request in
                (
                    Data(#"{"email":"native@example.com","email_verified":true}"#.utf8),
                    nativeHTTPResponse(for: request, statusCode: 200)
                )
            }
        )

        do {
            _ = try await service.fetchUsage(
                authJSON: .object([
                    "email": .string("native@example.com"),
                    "access_token": .string("test-access-token"),
                    "auth_method": .string("consumer"),
                    "antigravity_oauth_profile": .string("consumer"),
                    "client_id": .string(AntigravityOAuthProfile.consumer.publicClientID),
                    "antigravity_oauth_profile_refresh_verified_at": .number(1),
                    "expiry": .string("2099-01-01T00:00:00Z")
                ])
            )
            XCTFail("Expected the remote quota request to fail")
        } catch let error as AntigravityCredentialRefreshFailure {
            guard let underlying = error.underlying as? AppError,
                  case .network(let message) = underlying else {
                return XCTFail("Expected the native network category")
            }
            XCTAssertEqual(message, L10n.tr("error.antigravity.remote_quota_unavailable"))
        }
    }
}

final class AntigravityRemoteQuotaProtocolTests: XCTestCase {
    override func tearDown() {
        RecordingAntigravityRemoteURLProtocol.reset()
        super.tearDown()
    }

    func testConsumerUsesDailyQuotaSummaryWithItsOwnProjectAndBearer() async throws {
        let recorder = AntigravityRemoteRequestRecorder()
        RecordingAntigravityRemoteURLProtocol.install { request in
            recorder.append(request)
            switch request.url?.path {
            case "/v1internal:loadCodeAssist":
                return (200, Data(#"{"cloudaicompanionProject":"consumer-project","paidTier":{"id":"google-ai-pro"}}"#.utf8))
            case "/v1internal:retrieveUserQuotaSummary":
                return (200, quotaSummaryFixtureData())
            default:
                return (404, Data())
            }
        }

        let service = makeRemoteService()
        let result = try await service.fetchUsage(
            authJSON: verifiedRemoteAuth(profile: .consumer, accessToken: "consumer-access"),
            expectedEmail: "consumer@example.com"
        )

        XCTAssertEqual(result.usage.source, .antigravityRemoteQuota)
        XCTAssertEqual(result.usage.sourceAccountMatched, true)
        XCTAssertEqual(result.usage.quotaFamilies?.map(\.displayName), [
            "Gemini Models",
            "Claude and GPT models"
        ])
        XCTAssertEqual(result.usage.quotaFamilies?.first?.buckets.map(\.displayName), [
            "Five Hour Limit Remaining",
            "Weekly Limit Remaining"
        ])

        let requests = recorder.requests()
        XCTAssertEqual(requests.map(\.host), [
            "daily-cloudcode-pa.googleapis.com",
            "daily-cloudcode-pa.googleapis.com"
        ])
        XCTAssertEqual(requests.map(\.path), [
            "/v1internal:loadCodeAssist",
            "/v1internal:retrieveUserQuotaSummary"
        ])
        XCTAssertTrue(requests.allSatisfy {
            $0.authorization == "Bearer consumer-access"
                && $0.userAgent == "antigravity/hub/2.12.2 (os_type=darwin; arch=arm64)"
        })
        XCTAssertNil(requests.first?.userProject)
        XCTAssertEqual(
            (try requestJSON(requests[0])["metadata"] as? [String: Any])?["ideType"] as? String,
            "ANTIGRAVITY"
        )
        XCTAssertEqual(try requestJSON(requests[1])["project"] as? String, "consumer-project")
    }

    func testGCPUsesProductionEndpointAndSecondProjectQualifiedLoad() async throws {
        let recorder = AntigravityRemoteRequestRecorder()
        RecordingAntigravityRemoteURLProtocol.install { request in
            recorder.append(request)
            let body = (try? requestJSON(request)) ?? [:]
            switch request.url?.path {
            case "/v1internal:loadCodeAssist":
                if body["cloudaicompanionProject"] as? String == "explicit-project" {
                    return (200, Data(#"{"cloudaicompanionProject":"server-project"}"#.utf8))
                }
                return (200, Data(#"{"cloudaicompanionProject":"server-project","paidTier":{"id":"pro"}}"#.utf8))
            case "/v1internal:retrieveUserQuotaSummary":
                return (200, quotaSummaryFixtureData())
            default:
                return (404, Data())
            }
        }

        var auth = verifiedRemoteAuth(profile: .gcp, accessToken: "gcp-access")
        var object = try XCTUnwrap(auth.objectValue)
        object["antigravity_provider_project_id"] = .string("explicit-project")
        auth = .object(object)
        let service = makeRemoteService()
        _ = try await service.fetchUsage(authJSON: auth, expectedEmail: "consumer@example.com")

        let requests = recorder.requests()
        XCTAssertEqual(requests.map(\.host), [
            "cloudcode-pa.googleapis.com",
            "cloudcode-pa.googleapis.com",
            "cloudcode-pa.googleapis.com"
        ])
        XCTAssertEqual(requests.map(\.path), [
            "/v1internal:loadCodeAssist",
            "/v1internal:loadCodeAssist",
            "/v1internal:retrieveUserQuotaSummary"
        ])
        XCTAssertTrue(requests.allSatisfy { $0.userProject == "explicit-project" })
        XCTAssertEqual(try requestJSON(requests[0])["cloudaicompanionProject"] as? String, "explicit-project")
        XCTAssertEqual(try requestJSON(requests[1])["cloudaicompanionProject"] as? String, "server-project")
        XCTAssertEqual(try requestJSON(requests[2])["project"] as? String, "server-project")
    }

    func testForcedRefreshRotatesAndBindsWithoutPersistingClientSecret() async throws {
        let recorder = AntigravityRemoteRequestRecorder()
        RecordingAntigravityRemoteURLProtocol.install { request in
            recorder.append(request)
            switch request.url?.host {
            case "oauth2.googleapis.com":
                return (200, Data(#"{"access_token":"rotated-access","refresh_token":"rotated-refresh","token_type":"Bearer","expires_in":3600}"#.utf8))
            case "daily-cloudcode-pa.googleapis.com":
                if request.url?.path == "/v1internal:loadCodeAssist" {
                    return (200, Data(#"{"cloudaicompanionProject":"consumer-project","paidTier":{"id":"pro"}}"#.utf8))
                }
                return (200, quotaSummaryFixtureData())
            default:
                return (404, Data())
            }
        }
        let service = makeRemoteService(
            oauthCredentialResolver: { profile in
                AntigravityOAuthClientCredentials(
                    clientID: profile.publicClientID,
                    clientSecret: "fixture-secret"
                )
            }
        )
        var auth = verifiedRemoteAuth(profile: .consumer, accessToken: "old-access")
        var object = try XCTUnwrap(auth.objectValue)
        object.removeValue(forKey: AntigravityOAuthProfile.refreshVerificationStorageKey)
        object["refresh_token"] = .string("old-refresh")
        object["expiry"] = .string("1970-01-01T00:00:00Z")
        auth = .object(object)

        let refreshed = try await service.refreshStoredCredential(auth, force: true)
        XCTAssertEqual(refreshed["access_token"]?.stringValue, "rotated-access")
        XCTAssertEqual(refreshed["refresh_token"]?.stringValue, "rotated-refresh")
        XCTAssertEqual(refreshed["client_id"]?.stringValue, AntigravityOAuthProfile.consumer.publicClientID)
        XCTAssertNil(refreshed["client_secret"])
        XCTAssertTrue(AntigravityAuthRepository.isNativeVerifiedCredential(refreshed))

        let tokenRequest = try XCTUnwrap(recorder.requests().first(where: {
            $0.host == "oauth2.googleapis.com"
        }))
        let form = String(data: tokenRequest.body, encoding: .utf8) ?? ""
        XCTAssertTrue(form.contains("client_id=1071006060591-"))
        XCTAssertTrue(form.contains("refresh_token=old-refresh"))
    }

    func testUnboundRawTokenNeverDefaultsToConsumer() async throws {
        let recorder = AntigravityRemoteRequestRecorder()
        RecordingAntigravityRemoteURLProtocol.install { request in
            recorder.append(request)
            return (500, Data())
        }
        let service = makeRemoteService()
        let raw = JSONValue.object([
            "email": .string("consumer@example.com"),
            "access_token": .string("raw-access"),
            "refresh_token": .string("raw-refresh"),
            "expiry": .string("2099-01-01T00:00:00Z")
        ])

        do {
            _ = try await service.fetchUsage(authJSON: raw, expectedEmail: "consumer@example.com")
            XCTFail("A raw token without auth_method must not choose a client")
        } catch let error as AppError {
            guard case .unauthorized = error else {
                return XCTFail("Expected profile binding rejection")
            }
        }
        XCTAssertTrue(recorder.requests().isEmpty)
    }

    private func makeRemoteService(
        oauthCredentialResolver: @escaping AntigravityUsageService.OAuthCredentialResolver = {
            AntigravityOAuthClientCredentials(clientID: $0.publicClientID, clientSecret: "fixture-secret")
        }
    ) -> AntigravityUsageService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecordingAntigravityRemoteURLProtocol.self]
        return AntigravityUsageService(
            session: URLSession(configuration: configuration),
            dateProvider: AntigravityRemoteFixtureDateProvider(now: 1_800_000_000),
            nativeUsageService: failingNativeUsageService(),
            userInfoLoader: { request in
                let data = Data(#"{"email":"consumer@example.com","email_verified":true}"#.utf8)
                return (data, nativeHTTPResponse(for: request, statusCode: 200))
            },
            oauthCredentialResolver: oauthCredentialResolver
        )
    }

    private func verifiedRemoteAuth(
        profile: AntigravityOAuthProfile,
        accessToken: String
    ) -> JSONValue {
        .object([
            "email": .string("consumer@example.com"),
            "access_token": .string(accessToken),
            "refresh_token": .string("saved-refresh"),
            "expiry": .string("2099-01-01T00:00:00Z"),
            "auth_method": .string(profile.nativeAuthMethod),
            AntigravityOAuthProfile.profileStorageKey: .string(profile.rawValue),
            "client_id": .string(profile.publicClientID),
            AntigravityOAuthProfile.refreshVerificationStorageKey: .number(1),
            "antigravity_native_credential": .bool(true),
            "antigravity_native_credential_email": .string("consumer@example.com")
        ])
    }
}

private struct NativeLoginRequestRecord: Sendable {
    var path: String
    var port: Int?
    var body: Data
    var timeoutInterval: TimeInterval

    init(request: URLRequest) {
        path = request.url?.lastPathComponent ?? ""
        port = request.url?.port
        body = request.httpBody ?? Data()
        timeoutInterval = request.timeoutInterval
    }
}

private actor NativeLoginRequestRecorder {
    private var recordedRequests: [NativeLoginRequestRecord] = []

    func append(_ request: NativeLoginRequestRecord) {
        recordedRequests.append(request)
    }

    func requests() -> [NativeLoginRequestRecord] {
        recordedRequests
    }
}

private func nativeProcessListing() throws -> String {
    "4242 /private/var/folders/test/language_server --app_data_dir \"/Users/test/Library/Application Support/Antigravity\" --csrf_token=test-csrf"
}

private func nativeHTTPResponse(for request: URLRequest, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: request.url ?? URL(string: "https://127.0.0.1")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

private func failingNativeUsageService() -> AntigravityNativeUsageService {
    AntigravityNativeUsageService(
        processListing: nativeProcessListing,
        listeningPorts: { _ in [61_031] },
        requestLoader: { _ in throw URLError(.cannotConnectToHost) }
    )
}

private final class NativeLoginRemote403URLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: 403,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct AntigravityRemoteRequest: Sendable {
    var host: String
    var path: String
    var body: Data
    var authorization: String?
    var userProject: String?
    var userAgent: String?

    init(_ request: URLRequest) {
        host = request.url?.host ?? ""
        path = request.url?.path ?? ""
        body = request.httpBody ?? Data()
        authorization = request.value(forHTTPHeaderField: "Authorization")
        userProject = request.value(forHTTPHeaderField: "X-Goog-User-Project")
        userAgent = request.value(forHTTPHeaderField: "User-Agent")
    }
}

private final class AntigravityRemoteRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [AntigravityRemoteRequest] = []

    func append(_ request: URLRequest) {
        lock.lock()
        recorded.append(AntigravityRemoteRequest(request))
        lock.unlock()
    }

    func requests() -> [AntigravityRemoteRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }
}

private final class AntigravityRemoteProtocolState: @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) -> (Int, Data)

    private let lock = NSLock()
    private var handler: Handler?

    func install(_ handler: @escaping Handler) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func reset() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    func response(for request: URLRequest) -> (Int, Data) {
        lock.lock()
        let handler = handler
        lock.unlock()
        return handler?(request) ?? (500, Data())
    }
}

private final class RecordingAntigravityRemoteURLProtocol: URLProtocol, @unchecked Sendable {
    private static let state = AntigravityRemoteProtocolState()

    static func install(_ handler: @escaping AntigravityRemoteProtocolState.Handler) {
        state.install(handler)
    }

    static func reset() {
        state.reset()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        // URLSession may deliver POST bodies as a stream to URLProtocol.
        // Materialize it once so both recorder and fixture handler inspect
        // the same request, rather than treating an empty httpBody as no POST.
        var recordedRequest = request
        if recordedRequest.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(buffer, count: count)
            }
            recordedRequest.httpBody = body
        }
        let (statusCode, data) = Self.state.response(for: recordedRequest)
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct AntigravityRemoteFixtureDateProvider: DateProviding {
    var now: Int64

    func unixSecondsNow() -> Int64 { now }
}

private func requestJSON(_ request: AntigravityRemoteRequest) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: request.body) as? [String: Any] ?? [:]
}

private func requestJSON(_ request: URLRequest) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] ?? [:]
}

private func quotaSummaryFixtureData() -> Data {
    Data(
        #"{"response":{"groups":[{"displayName":"Gemini Models","buckets":[{"bucketId":"five","displayName":"Five Hour Limit Remaining","remainingFraction":0.5,"window":"5h"},{"bucketId":"weekly","displayName":"Weekly Limit Remaining","remainingFraction":0.75,"window":"P7D"}]},{"displayName":"Claude and GPT models","buckets":[{"bucketId":"third","displayName":"Other Limit","remainingFraction":1.0,"window":"5h"}]}]}}"#.utf8
    )
}

import Foundation
import Security

struct AntigravityNativeUsageResult: Equatable, Sendable {
    var email: String
    var planType: String?
    var usage: UsageSnapshot
}

/// A portable credential is safe to retain for a future native switch only
/// after its bearer token and the live local RPC report the same identity.
struct AntigravityNativeCredentialVerification: Equatable, Sendable {
    var email: String
    var authJSON: JSONValue
}

/// Remote quota may fail after OAuth has successfully rotated and identity-
/// bound a credential. Carry that safe-to-store result back to the coordinator
/// without putting it in a localized error description or diagnostic log.
struct AntigravityCredentialRefreshFailure: Error {
    let verifiedAuthJSON: JSONValue
    let underlying: Error
}

/// Reads AntiGravity's local language-server endpoints. It never writes
/// AntiGravity credentials, starts a process, or terminates a user process.
final class AntigravityNativeUsageService: @unchecked Sendable {
    private enum ProcessKind: Sendable {
        case app
        case agy

        var snapshotSource: UsageSnapshotSource {
            switch self {
            case .app: .antigravityNativeSummary
            case .agy: .antigravityAgySummary
            }
        }
    }

    private struct Candidate: Sendable {
        var pid: Int
        var csrfToken: String
        var kind: ProcessKind
        var httpPort: Int?
        var httpCsrfToken: String
    }

    private struct Endpoint: Sendable {
        var scheme: String
        var port: Int
        var csrfToken: String
    }

    typealias ProcessListing = @Sendable () throws -> String
    typealias ListeningPorts = @Sendable (Int) throws -> [Int]
    typealias RequestLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    private let processListing: ProcessListing
    private let listeningPorts: ListeningPorts
    private let requestLoader: RequestLoader
    private let dateProvider: DateProviding

    init(
        processListing: @escaping ProcessListing = AntigravityNativeUsageService.defaultProcessListing,
        listeningPorts: @escaping ListeningPorts = AntigravityNativeUsageService.defaultListeningPorts,
        requestLoader: @escaping RequestLoader = AntigravityNativeUsageService.defaultRequestLoader,
        dateProvider: DateProviding = SystemDateProvider()
    ) {
        self.processListing = processListing
        self.listeningPorts = listeningPorts
        self.requestLoader = requestLoader
        self.dateProvider = dateProvider
    }

    func fetchCurrentUsage(expectedEmail: String? = nil) async throws -> AntigravityNativeUsageResult {
        let candidates = Self.parseCandidates(try processListing())
        guard !candidates.isEmpty else {
            throw AppError.fileNotFound(L10n.tr("error.antigravity.native_session_unavailable"))
        }

        var lastError: Error = AppError.network(L10n.tr("error.antigravity.native_quota_unavailable"))
        for candidate in candidates {
            let endpoints: [Endpoint]
            do {
                let https = try listeningPorts(candidate.pid).map {
                    Endpoint(scheme: "https", port: $0, csrfToken: candidate.csrfToken)
                }
                let http = candidate.httpPort.map {
                    Endpoint(scheme: "http", port: $0, csrfToken: candidate.httpCsrfToken)
                }
                endpoints = https + (http.map { [ $0 ] } ?? [])
            } catch {
                lastError = error
                continue
            }
            for endpoint in endpoints {
                do {
                    return try await load(
                        candidate: candidate,
                        endpoint: endpoint,
                        expectedEmail: expectedEmail
                    )
                } catch {
                    // A language server can own both the HTTP fallback and HTTPS
                    // connect port. Try every endpoint before rejecting its PID.
                    lastError = error
                }
            }
        }
        throw lastError
    }

    /// Starts the native sign-in flow through the already running language
    /// server. `isGcpTos` is deliberately false: Copool neither accepts nor
    /// records Google's terms on the user's behalf.
    ///
    /// Endpoint discovery is read-only and may wait while the app finishes
    /// launching. Once one endpoint is confirmed, this method makes exactly
    /// one `Login` call. In particular, a failed or timed-out Login is not
    /// retried against another port or candidate, since that could open more
    /// than one OAuth browser flow.
    func beginBrowserLogin(
        readinessTimeout: TimeInterval = 35,
        responseTimeout: TimeInterval = 10 * 60
    ) async throws {
        let endpoint = try await confirmedEndpointForBrowserLogin(
            readinessTimeout: readinessTimeout
        )
        try Task.checkCancellation()

        // `Login` has a real native RPC response. Decode it rather than
        // treating a 2xx HTTP acknowledgement as proof that login started or
        // completed; identity and quota are still verified by later polling.
        let response = try await request(
            path: "Login",
            endpoint: endpoint,
            body: .object(["isGcpTos": .bool(false)]),
            timeoutInterval: max(1, responseTimeout)
        )
        guard Self.hasValidBrowserLogin(response) else {
            // A 200 transport response can still carry a failed auth result.
            // Do not surface provider details here (they may contain sensitive
            // state), and never retry this Login on another endpoint.
            throw AppError.unauthorized(L10n.tr("error.antigravity.native_login_failed"))
        }
        try Task.checkCancellation()
    }

    /// Finds an app-owned language-server endpoint using only the read-only
    /// GetUnleashData RPC. This deliberately performs no Login during retries.
    private func confirmedEndpointForBrowserLogin(
        readinessTimeout: TimeInterval
    ) async throws -> Endpoint {
        let deadline = Date().addingTimeInterval(max(1, readinessTimeout))
        var lastError: Error = AppError.network(L10n.tr("error.antigravity.native_session_unavailable"))

        while Date() < deadline {
            try Task.checkCancellation()
            do {
                let candidates = Self.parseCandidates(try processListing())
                guard !candidates.isEmpty else {
                    throw AppError.fileNotFound(L10n.tr("error.antigravity.native_session_unavailable"))
                }

                for candidate in candidates {
                    let endpoints: [Endpoint]
                    do {
                        let https = try listeningPorts(candidate.pid).map {
                            Endpoint(scheme: "https", port: $0, csrfToken: candidate.csrfToken)
                        }
                        let http = candidate.httpPort.map {
                            Endpoint(scheme: "http", port: $0, csrfToken: candidate.httpCsrfToken)
                        }
                        endpoints = https + (http.map { [$0] } ?? [])
                    } catch {
                        lastError = error
                        continue
                    }

                    for endpoint in endpoints {
                        try Task.checkCancellation()
                        do {
                            _ = try await requestData(
                                path: "GetUnleashData",
                                endpoint: endpoint,
                                body: .object([:])
                            )
                            return endpoint
                        } catch {
                            lastError = error
                        }
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }

            try await Task.sleep(for: .seconds(1))
        }
        throw lastError
    }

    private func load(
        candidate: Candidate,
        endpoint: Endpoint,
        expectedEmail: String?
    ) async throws -> AntigravityNativeUsageResult {
        // A successful connect endpoint keeps us from accepting an unrelated
        // localhost listener which happens to share a port.
        _ = try await requestData(
            path: "GetUnleashData",
            endpoint: endpoint,
            body: .object([:])
        )
        let statusPayload = try await request(
            path: "GetUserStatus",
            endpoint: endpoint,
            body: Self.metadataBody
        )
        guard let email = Self.email(fromUserStatus: statusPayload) else {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_identity_unavailable"))
        }
        if let expectedEmail,
           Self.normalizedEmail(expectedEmail) != Self.normalizedEmail(email) {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_session_mismatch"))
        }

        // This is the only endpoint accepted as a complete AntiGravity quota
        // source. GetUserStatus/model data is not substituted for this summary.
        let quotaPayload = try await request(
            path: "RetrieveUserQuotaSummary",
            endpoint: endpoint,
            body: .object(["forceRefresh": .bool(true)])
        )
        let snapshot = try Self.usageSnapshot(
            fromQuotaSummary: quotaPayload,
            fetchedAt: dateProvider.unixSecondsNow(),
            planType: Self.planType(fromUserStatus: statusPayload),
            source: candidate.kind.snapshotSource,
            sourceAccountMatched: true
        )
        return AntigravityNativeUsageResult(email: email, planType: snapshot.planType, usage: snapshot)
    }

    private func request(
        path: String,
        endpoint: Endpoint,
        body: JSONValue,
        timeoutInterval: TimeInterval = 8
    ) async throws -> JSONValue {
        let data = try await requestData(
            path: path,
            endpoint: endpoint,
            body: body,
            timeoutInterval: timeoutInterval
        )
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_quota_unavailable"))
        }
    }

    private func requestData(
        path: String,
        endpoint: Endpoint,
        body: JSONValue,
        timeoutInterval: TimeInterval = 8
    ) async throws -> Data {
        guard (endpoint.scheme == "https" || endpoint.scheme == "http"),
              (1...65_535).contains(endpoint.port),
              let url = URL(
                string: "\(endpoint.scheme)://127.0.0.1:\(endpoint.port)/exa.language_server_pb.LanguageServerService/\(path)"
              )
        else {
            throw AppError.network(L10n.tr("error.antigravity.native_quota_unavailable"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = max(1, timeoutInterval)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        if !endpoint.csrfToken.isEmpty {
            request.setValue(endpoint.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await requestLoader(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AppError.network(L10n.tr("error.antigravity.native_request_failed_format", String(status)))
        }
        return data
    }

    private static func parseCandidates(_ processOutput: String) -> [Candidate] {
        processOutput.split(separator: "\n").compactMap { rawLine in
            let line = String(rawLine)
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count == 2, let pid = Int(parts[0]) else { return nil }
            let command = String(parts[1])
            let lower = command.lowercased()
            let isLanguageServer = lower.contains("language_server") || lower.contains("language-server")
            let appDataDirectory = (argumentValue(named: "app_data_dir", in: command) ?? "").lowercased()
            let isApp = isLanguageServer
                && (isAntigravityAppDataDirectory(appDataDirectory) || lower.contains("/antigravity.app/"))
                && !lower.contains("antigravity-ide")
            let isAgy = lower.contains("/agy") || lower.hasPrefix("agy ") || lower == "agy"
            guard isApp || isAgy else { return nil }
            let csrf = isApp ? argumentValue(named: "csrf_token", in: command) ?? "" : ""
            guard !isApp || !csrf.isEmpty else { return nil }
            let httpPort = argumentValue(named: "extension_server_port", in: command).flatMap(Int.init)
            let httpCsrf = argumentValue(named: "extension_server_csrf_token", in: command) ?? csrf
            return Candidate(
                pid: pid,
                csrfToken: csrf,
                kind: isApp ? .app : .agy,
                httpPort: httpPort,
                httpCsrfToken: httpCsrf
            )
        }
        .sorted { left, right in
            if left.kind != right.kind {
                return left.kind == .app
            }
            return left.pid < right.pid
        }
    }

    private static func hasValidBrowserLogin(_ payload: JSONValue) -> Bool {
        let authResult = payload["authResult"]
            ?? payload["auth_result"]
            ?? payload["response"]?["authResult"]
            ?? payload["response"]?["auth_result"]
        return authResult?["hasValidAuth"]?.boolValue == true
            || authResult?["has_valid_auth"]?.boolValue == true
    }

    static func usageSnapshot(
        fromQuotaSummary payload: JSONValue,
        fetchedAt: Int64,
        planType: String?,
        source: UsageSnapshotSource,
        sourceAccountMatched: Bool
    ) throws -> UsageSnapshot {
        let groups = payload["response"]?["groups"]?.arrayValue
            ?? payload["groups"]?.arrayValue
            ?? []
        var families: [UsageQuotaFamily] = []

        for (groupIndex, group) in groups.enumerated() {
            let displayName = Self.trimmed(group["displayName"]?.stringValue)
            let buckets = (group["buckets"]?.arrayValue ?? []).enumerated().compactMap { bucketIndex, bucket -> UsageQuotaBucket? in
                let identifier = Self.trimmed(bucket["bucketId"]?.stringValue)
                let label = Self.trimmed(bucket["displayName"]?.stringValue)
                guard !identifier.isEmpty || !label.isEmpty else { return nil }
                let disabled = bucket["disabled"]?.boolValue == true
                let remaining = Self.number(bucket["remainingFraction"])
                    ?? Self.number(bucket["remaining"]?["remainingFraction"])
                let validRemaining = remaining.flatMap { value -> Double? in
                    guard value.isFinite, (0...1).contains(value), !disabled else { return nil }
                    return value
                }
                let used = validRemaining.map { (1 - $0) * 100 }
                let resetAt = Self.parseReset(
                    bucket["resetTime"]?.stringValue
                        ?? bucket["remaining"]?["resetTime"]?.stringValue
                )
                let window = Self.trimmed(bucket["window"]?.stringValue)
                let description = Self.trimmed(bucket["description"]?.stringValue)
                let recognizedWindow = Self.windowSeconds(
                    from: window,
                    bucketID: identifier,
                    displayName: label
                )
                return UsageQuotaBucket(
                    id: identifier.isEmpty ? "bucket-\(groupIndex)-\(bucketIndex)" : identifier,
                    // Persist the server's canonical label.  Rendering the
                    // short localized 5h/1-week label belongs to UI, tray and
                    // widget presentation, never to a store snapshot.
                    displayName: label.isEmpty ? identifier : label,
                    usedPercent: used,
                    resetAt: resetAt,
                    windowSeconds: recognizedWindow,
                    resetDescription: description.isEmpty ? nil : description,
                    isUsageKnown: validRemaining != nil
                )
            }
            guard !buckets.isEmpty else { continue }
            families.append(
                UsageQuotaFamily(
                    id: displayName.isEmpty ? "group-\(groupIndex)" : "group-\(displayName.lowercased())",
                    displayName: displayName.isEmpty ? "Quota" : displayName,
                    buckets: buckets.sorted(by: Self.compareBuckets)
                )
            )
        }

        guard families.contains(where: { !$0.buckets.isEmpty }) else {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_quota_unavailable"))
        }
        let known = families.flatMap(\.buckets).filter { $0.isUsageKnown && $0.usedPercent != nil }
        guard !known.isEmpty else {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_quota_unavailable"))
        }
        return UsageSnapshot(
            fetchedAt: fetchedAt,
            planType: planType,
            fiveHour: Self.legacyWindow(from: known, cadenceRank: 0),
            oneWeek: Self.legacyWindow(from: known, cadenceRank: 1),
            credits: nil,
            quotaFamilies: families,
            source: source,
            sourceAccountMatched: sourceAccountMatched
        )
    }

    static func email(fromUserStatus payload: JSONValue) -> String? {
        let status = payload["userStatus"] ?? payload["response"]?["userStatus"] ?? payload
        return normalizedEmail(status["email"]?.stringValue ?? status["user"]?["email"]?.stringValue)
    }

    static func planType(fromUserStatus payload: JSONValue) -> String? {
        let status = payload["userStatus"] ?? payload["response"]?["userStatus"] ?? payload
        let candidates = [
            status["userTier"]?["name"]?.stringValue,
            status["userTier"]?["preferredName"]?.stringValue,
            status["planStatus"]?["planInfo"]?["planName"]?.stringValue,
            status["planStatus"]?["planInfo"]?["name"]?.stringValue
        ]
        return AntigravityUsageService.normalizedPlanType(
            from: candidates.compactMap { $0 }.joined(separator: " ")
        )
    }

    private static let metadataBody = JSONValue.object([
        "metadata": .object([
            "ideName": .string("antigravity"),
            "extensionName": .string("antigravity"),
            "ideVersion": .string("unknown"),
            "locale": .string("en")
        ])
    ])

    private static func compareBuckets(_ left: UsageQuotaBucket, _ right: UsageQuotaBucket) -> Bool {
        if left.cadenceRank != right.cadenceRank {
            return left.cadenceRank < right.cadenceRank
        }
        return left.id.localizedCaseInsensitiveCompare(right.id) == .orderedAscending
    }

    private static func legacyWindow(from buckets: [UsageQuotaBucket], cadenceRank: Int) -> UsageWindow? {
        guard let selected = buckets
            .filter({ $0.cadenceRank == cadenceRank })
            .sorted(by: { ($0.usedPercent ?? -1) > ($1.usedPercent ?? -1) })
            .first,
              let usedPercent = selected.usedPercent
        else { return nil }
        return UsageWindow(
            usedPercent: usedPercent,
            windowSeconds: selected.windowSeconds ?? 0,
            resetAt: selected.resetAt
        )
    }

    private static func windowSeconds(from window: String, bucketID: String, displayName: String) -> Int64? {
        let metadata = "\(window) \(bucketID)".lowercased()
        if metadata.contains("5h") || metadata.contains("five_hour") || metadata.contains("pt5h") {
            return 5 * 60 * 60
        }
        if metadata.contains("week") || metadata.contains("p7d") {
            return 7 * 24 * 60 * 60
        }
        // The native response sometimes omits `window` but exposes these
        // exact human-readable bucket names. Do not turn arbitrary labels into
        // fixed cadence labels; only these explicit names are recognized.
        switch displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "five hour limit remaining":
            return 5 * 60 * 60
        case "weekly limit remaining":
            return 7 * 24 * 60 * 60
        default:
            return nil
        }
    }

    private static func argumentValue(named name: String, in command: String) -> String? {
        let pattern = "(?:^|\\s)--\(NSRegularExpression.escapedPattern(for: name))(?:=|\\s+)(?:\"([^\"]*)\"|'([^']*)'|([^\\s]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(command.startIndex..<command.endIndex, in: command)
        guard let match = regex.firstMatch(in: command, range: range) else { return nil }
        for captureIndex in 1...3 {
            guard let capture = Range(match.range(at: captureIndex), in: command) else { continue }
            return String(command[capture])
        }
        return nil
    }

    private static func isAntigravityAppDataDirectory(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized == "antigravity"
            || normalized.hasSuffix("/antigravity")
            || normalized.hasSuffix("\\antigravity")
            || normalized.hasSuffix(".antigravity")
    }

    private static func number(_ value: JSONValue?) -> Double? {
        if let number = value?.doubleValue { return number }
        if let text = value?.stringValue, let number = Double(text) { return number }
        return nil
    }

    private static func parseReset(_ value: String?) -> Int64? {
        let value = trimmed(value)
        guard !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return Int64(date.timeIntervalSince1970) }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return Int64(date.timeIntervalSince1970) }
        if let numeric = Double(value) {
            return Int64(numeric > 10_000_000_000 ? numeric / 1_000 : numeric)
        }
        return nil
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        let normalized = trimmed(value).lowercased()
        return normalized.contains("@") ? normalized : nil
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func defaultProcessListing() throws -> String {
        try CommandRunner.run("/bin/ps", arguments: ["-ax", "-o", "pid=,command="], timeout: 2).stdout
    }

    private static func defaultListeningPorts(pid: Int) throws -> [Int] {
        let lsofPaths = ["/usr/sbin/lsof", "/usr/bin/lsof"]
        guard let lsof = lsofPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw AppError.fileNotFound(L10n.tr("error.antigravity.native_session_unavailable"))
        }
        let result = try CommandRunner.run(
            lsof,
            arguments: ["-nP", "-a", "-p", String(pid), "-iTCP", "-sTCP:LISTEN"],
            timeout: 2
        )
        let pattern = #":(\d+)\s+\(LISTEN\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(result.stdout.startIndex..<result.stdout.endIndex, in: result.stdout)
        var ports = Set<Int>()
        regex.enumerateMatches(in: result.stdout, range: range) { match, _, _ in
            guard let match,
                  let capture = Range(match.range(at: 1), in: result.stdout),
                  let port = Int(result.stdout[capture])
            else { return }
            ports.insert(port)
        }
        guard !ports.isEmpty else {
            throw AppError.network(L10n.tr("error.antigravity.native_session_unavailable"))
        }
        return ports.sorted()
    }

    private static func defaultRequestLoader(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await AntigravityLoopbackHTTPClient.shared.data(for: request)
    }
}

private final class AntigravityLoopbackTrustDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let protectionSpace = challenge.protectionSpace
        guard protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              protectionSpace.host == "127.0.0.1",
              let trust = protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private enum AntigravityLoopbackHTTPClient {
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        // The language server is a loopback-only peer. Explicitly disable
        // inherited system proxy settings so this request cannot be routed to
        // a remote proxy (or fail because one intercepts 127.0.0.1).
        configuration.connectionProxyDictionary = [:]
        return URLSession(
            configuration: configuration,
            delegate: AntigravityLoopbackTrustDelegate(),
            delegateQueue: nil
        )
    }()
}

/// The native language server's OAuth mode is part of its credential envelope,
/// not an inference Copool can make from a model, plan, e-mail, or old saved
/// account.  Keeping this mapping small and explicit prevents a consumer grant
/// from ever being refreshed through the GCP client (or vice versa).
enum AntigravityOAuthProfile: String, Codable, Sendable {
    case consumer
    case gcp

    static let profileStorageKey = "antigravity_oauth_profile"
    static let refreshVerificationStorageKey = "antigravity_oauth_profile_refresh_verified_at"

    var nativeAuthMethod: String { rawValue }

    var publicClientID: String {
        switch self {
        case .consumer:
            return "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
        case .gcp:
            return "884354919052-36trc1jjb3tguiac32ov6cod268c5blh.apps.googleusercontent.com"
        }
    }

    var cloudCodeBaseURL: String {
        switch self {
        case .consumer:
            return "https://daily-cloudcode-pa.googleapis.com/v1internal:"
        case .gcp:
            return "https://cloudcode-pa.googleapis.com/v1internal:"
        }
    }

    /// Resolves only an explicit native mode.  A missing `auth_method` is
    /// intentionally not treated as consumer: raw historical tokens must be
    /// reauthorized or independently bound before they can be refreshed.
    static func resolve(from authJSON: JSONValue) -> AntigravityOAuthProfile? {
        guard let object = authJSON.objectValue,
              let method = object["auth_method"]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
              let profile = AntigravityOAuthProfile(rawValue: method)
        else {
            return nil
        }

        if let saved = object[profileStorageKey]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           saved != profile.rawValue {
            return nil
        }
        if let clientID = object["client_id"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !clientID.isEmpty,
           clientID != profile.publicClientID {
            return nil
        }
        return profile
    }

    static func hasRefreshVerifiedBinding(_ authJSON: JSONValue) -> Bool {
        guard let profile = resolve(from: authJSON),
              let object = authJSON.objectValue,
              object[profileStorageKey]?.stringValue == profile.rawValue,
              object["client_id"]?.stringValue == profile.publicClientID,
              let verifiedAt = object[refreshVerificationStorageKey]?.doubleValue,
              verifiedAt.isFinite,
              verifiedAt > 0
        else {
            return false
        }
        return true
    }

    func binding(_ object: [String: JSONValue], verifiedAt: Int64? = nil) -> [String: JSONValue] {
        var bound = object
        bound["auth_method"] = .string(nativeAuthMethod)
        bound[Self.profileStorageKey] = .string(rawValue)
        bound["client_id"] = .string(publicClientID)
        // Client secrets are resolved only in memory during a refresh.  Never
        // retain one inside Copool's auth JSON, even if an old import had it.
        bound.removeValue(forKey: "client_secret")
        if let verifiedAt {
            bound[Self.refreshVerificationStorageKey] = .number(Double(verifiedAt))
        }
        return bound
    }

    static func explicitProviderProjectID(from authJSON: JSONValue) -> String? {
        guard let object = authJSON.objectValue else { return nil }
        let nested = object["antigravity_provider"]?.objectValue
            ?? object["provider"]?.objectValue
        let candidates = [
            object["antigravity_provider_project_id"]?.stringValue,
            nested?["projectID"]?.stringValue,
            nested?["project_id"]?.stringValue
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    static func configuredCloudCodeBaseURL(
        from authJSON: JSONValue,
        profile: AntigravityOAuthProfile
    ) -> String {
        guard let value = authJSON["antigravity_cloud_code_base_url"]?.stringValue?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value),
              url.scheme == "https",
              let host = url.host?.lowercased(),
              host == "cloudcode-pa.googleapis.com" || host == "daily-cloudcode-pa.googleapis.com"
        else {
            return profile.cloudCodeBaseURL
        }

        let trimmed = value.hasSuffix("/") ? String(value.dropLast()) : value
        return trimmed.hasSuffix("v1internal:") ? trimmed : "\(trimmed)/v1internal:"
    }
}

struct AntigravityOAuthClientCredentials: Sendable {
    let clientID: String
    let clientSecret: String
}

/// Resolves the native OAuth client secret from the exact public configuration
/// reference in the known Antigravity language-server binary.  The file is
/// verified before it is mapped, no strings are searched, and the secret never
/// leaves memory or enters an error/log/store payload.  Any version/hash/layout
/// mismatch fails closed and requires a fresh native sign-in instead.
enum AntigravityNativeOAuthClientResolver {
    private struct BinaryProfile {
        let version: String
        let sha256: String
        let consumerAddress: UInt64
        let gcpAddress: UInt64
    }
    private static let supportedBinaries = [
        BinaryProfile(version: "2.12.2", sha256: "ff6c9e32ac5d8712476b80e6ce9644a73b5689de991810fc906efa3c0254650e", consumerAddress: 0x1029b8f72, gcpAddress: 0x1029b8f95),
        BinaryProfile(version: "2.13.0", sha256: "5aa1a93c49bc0149cab4e3d8ae811223041a1564a1e0fd822e9b6badb443b5aa", consumerAddress: 0x102a16e3a, gcpAddress: 0x102a16e5d),
        BinaryProfile(version: "2.14.0", sha256: "978c3352f64c2c6bd627640392539aa29c1123b7f95b1fdde024ded96f30cf31", consumerAddress: 0x102aeb6f4, gcpAddress: 0x102aeb717)
    ]
    private static let languageServerURL = URL(
        fileURLWithPath: "/Applications/Antigravity.app/Contents/Resources/bin/language_server"
    )
    private static let appInfoURL = URL(
        fileURLWithPath: "/Applications/Antigravity.app/Contents/Info.plist"
    )

    private struct SecretReference {
        let virtualAddress: UInt64
        let length: Int
    }

    static func credentials(for profile: AntigravityOAuthProfile) throws -> AntigravityOAuthClientCredentials {
        let binary = try verifyKnownBinary()
        let data: Data
        do {
            data = try Data(contentsOf: languageServerURL, options: [.mappedIfSafe])
        } catch {
            throw unavailableProfileError()
        }

        let reference: SecretReference
        switch profile {
        case .consumer:
            reference = SecretReference(virtualAddress: binary.consumerAddress, length: 35)
        case .gcp:
            reference = SecretReference(virtualAddress: binary.gcpAddress, length: 35)
        }
        guard let bytes = machOBytes(
            atVirtualAddress: reference.virtualAddress,
            length: reference.length,
            from: data
        ),
        let secret = String(data: bytes, encoding: .utf8),
        secret.utf8.count == reference.length,
        !secret.isEmpty
        else {
            throw unavailableProfileError()
        }
        return AntigravityOAuthClientCredentials(
            clientID: profile.publicClientID,
            clientSecret: secret
        )
    }

    private static func verifyKnownBinary() throws -> BinaryProfile {
        guard let info = NSDictionary(contentsOf: appInfoURL),
              let version = info["CFBundleShortVersionString"] as? String,
              let binary = supportedBinaries.first(where: { $0.version == version })
        else {
            throw unavailableProfileError()
        }
        let result: CommandResult
        do {
            result = try CommandRunner.run(
                "/usr/bin/shasum",
                arguments: ["-a", "256", languageServerURL.path],
                timeout: 20
            )
        } catch {
            throw unavailableProfileError()
        }
        let digest = result.stdout.split(whereSeparator: { $0 == " " || $0 == "\t" }).first
        guard result.status == 0,
              digest?.lowercased() == binary.sha256
        else {
            throw unavailableProfileError()
        }
        return binary
    }

    private static func unavailableProfileError() -> AppError {
        .unauthorized(L10n.tr("error.antigravity.native_oauth_profile_unavailable"))
    }

    /// Maps a fixed Mach-O virtual address through a 64-bit segment command.
    /// The parser has no string-search fallback: an unknown binary layout is a
    /// hard failure instead of a chance to borrow a nearby client secret.
    private static func machOBytes(
        atVirtualAddress address: UInt64,
        length: Int,
        from data: Data
    ) -> Data? {
        guard length > 0,
              data.count >= 32,
              let magic = littleEndian32(data, at: 0),
              magic == 0xfeedfacf,
              let commandCount = littleEndian32(data, at: 16)
        else {
            return nil
        }
        var cursor = 32
        for _ in 0..<commandCount {
            guard let command = littleEndian32(data, at: cursor),
                  let commandSize = littleEndian32(data, at: cursor + 4),
                  commandSize >= 8,
                  cursor <= data.count - Int(commandSize)
            else {
                return nil
            }
            if command == 0x19,
               commandSize >= 72,
               let vmAddress = littleEndian64(data, at: cursor + 24),
               let fileOffset = littleEndian64(data, at: cursor + 40),
               let fileSize = littleEndian64(data, at: cursor + 48),
               address >= vmAddress {
                let difference = address.subtractingReportingOverflow(vmAddress)
                let relative = difference.partialValue
                if !difference.overflow,
                   relative <= fileSize,
                   UInt64(length) <= fileSize - relative,
                   let start = Int(exactly: fileOffset + relative),
                   start >= 0,
                   start <= data.count - length {
                    return data.subdata(in: start..<(start + length))
                }
            }
            cursor += Int(commandSize)
        }
        return nil
    }

    private static func littleEndian32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset <= data.count - 4 else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func littleEndian64(_ data: Data, at offset: Int) -> UInt64? {
        guard offset >= 0, offset <= data.count - 8 else { return nil }
        return (0..<8).reduce(UInt64(0)) { value, index in
            value | (UInt64(data[offset + index]) << UInt64(index * 8))
        }
    }
}

/// Remote OAuth is account-scoped fallback only. Model availability is never
/// rendered as a synthetic 0%-used quota.
final class AntigravityUsageService: @unchecked Sendable {
    typealias UserInfoLoader = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias OAuthCredentialResolver = @Sendable (AntigravityOAuthProfile) throws -> AntigravityOAuthClientCredentials

    /// Compatibility constant for callers that explicitly model a consumer
    /// account. Production requests select the base from `auth_method` instead.
    static let cloudCodeBaseURL = AntigravityOAuthProfile.consumer.cloudCodeBaseURL

    private let session: URLSession
    private let dateProvider: DateProviding
    private let nativeUsageService: AntigravityNativeUsageService
    private let userInfoLoader: UserInfoLoader
    private let oauthCredentialResolver: OAuthCredentialResolver

    init(
        session: URLSession = BackgroundNetworkSession.shared,
        dateProvider: DateProviding = SystemDateProvider(),
        nativeUsageService: AntigravityNativeUsageService = AntigravityNativeUsageService(),
        userInfoLoader: UserInfoLoader? = nil,
        oauthCredentialResolver: @escaping OAuthCredentialResolver = {
            try AntigravityNativeOAuthClientResolver.credentials(for: $0)
        }
    ) {
        self.session = session
        self.dateProvider = dateProvider
        self.nativeUsageService = nativeUsageService
        self.userInfoLoader = userInfoLoader ?? { request in
            try await session.data(for: request)
        }
        self.oauthCredentialResolver = oauthCredentialResolver
    }

    func fetchCurrentNativeUsage() async throws -> AntigravityNativeUsageResult {
        try await loadNativeUsage(expectedEmail: nil)
    }

    func fetchNativeUsage(expectedEmail: String) async throws -> AntigravityNativeUsageResult {
        try await loadNativeUsage(expectedEmail: expectedEmail)
    }

    /// Refreshes only a credential's own OAuth grant when its bearer is close
    /// to expiry. It never borrows a client from another account and does not
    /// read, write, launch, or stop the native application. Callers stage the
    /// returned value only after their surrounding transaction succeeds.
    func refreshStoredCredentialIfNeeded(_ authJSON: JSONValue) async throws -> JSONValue {
        try await refreshStoredCredential(authJSON, force: false)
    }

    /// Production refresh path shared by switch preflight and the narrow QA
    /// driver. `force` means "perform this account's one profile-bound OAuth
    /// refresh now"; it never changes which client/profile is selected.
    func refreshStoredCredential(
        _ authJSON: JSONValue,
        force: Bool
    ) async throws -> JSONValue {
        try await prepareStoredCredentialForUse(authJSON, forceRefresh: force)
    }

    /// Invokes the native language-server browser login. The only request field
    /// is `isGcpTos: false`; the user completes any consent in the browser.
    func beginNativeBrowserLogin(
        readinessTimeout: TimeInterval = 35,
        responseTimeout: TimeInterval = 10 * 60
    ) async throws {
        try await nativeUsageService.beginBrowserLogin(
            readinessTimeout: readinessTimeout,
            responseTimeout: responseTimeout
        )
    }

    /// Reads exactly the native Keychain/FileTokenStorage credential and binds
    /// its bearer token to a just-observed local-RPC identity through Google's
    /// read-only userinfo endpoint. A mismatch never returns the token.
    func verifyCurrentNativeCredential(
        repository: AntigravityAuthRepository,
        matchingNativeEmail nativeEmail: String,
        credentialAccess: AntigravityNativeCredentialAccess
    ) async throws -> AntigravityNativeCredentialVerification {
        let expectedEmail = Self.normalizedEmail(nativeEmail)
        guard let expectedEmail else {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_identity_unavailable"))
        }
        var lastError: Error = AppError.unauthorized(
            L10n.tr("error.antigravity.native_oauth_profile_unavailable")
        )
        for candidate in try repository.readCurrentAuthCandidates(access: credentialAccess) {
            do {
                guard let profile = AntigravityOAuthProfile.resolve(from: candidate.authJSON) else {
                    throw AppError.unauthorized(L10n.tr("error.antigravity.native_oauth_profile_unavailable"))
                }
                guard var object = candidate.authJSON.objectValue else {
                    throw AppError.invalidData(L10n.tr("error.antigravity.auth_json_invalid"))
                }

                // First-time native bindings are deliberately refreshed with
                // the one client selected by the envelope. A matching e-mail
                // alone is not sufficient evidence for an old raw token.
                var boundAuth = candidate.authJSON
                if Self.accessTokenNeedsRefresh(in: boundAuth)
                    || !AntigravityOAuthProfile.hasRefreshVerifiedBinding(boundAuth) {
                    boundAuth = try await refreshAccessToken(boundAuth, profile: profile)
                    guard let refreshedObject = boundAuth.objectValue else {
                        throw AppError.invalidData(L10n.tr("error.antigravity.auth_json_invalid"))
                    }
                    object = refreshedObject
                }

                let accessToken = Self.trimmed(object["access_token"]?.stringValue)
                guard !accessToken.isEmpty else {
                    throw AppError.unauthorized(L10n.tr("error.antigravity.native_identity_unavailable"))
                }
                let userInfoEmail = try await fetchGoogleUserInfoEmail(accessToken: accessToken)
                guard Self.normalizedEmail(userInfoEmail) == expectedEmail else {
                    throw AppError.invalidData(L10n.tr("error.antigravity.native_session_mismatch"))
                }

                object = profile.binding(object, verifiedAt: dateProvider.unixSecondsNow())
                // These fields belong only to Copool's account store.
                // `stageNativeAuth` strips them before writing the native
                // envelope, while requiring this exact proof later.
                object["email"] = .string(userInfoEmail)
                object["antigravity_native_credential"] = .bool(true)
                object["antigravity_native_credential_origin"] = .string("native-rpc-userinfo")
                object["antigravity_native_credential_email"] = .string(userInfoEmail)
                object["antigravity_native_credential_verified_at"] = .number(
                    Double(dateProvider.unixSecondsNow())
                )
                return AntigravityNativeCredentialVerification(
                    email: userInfoEmail,
                    authJSON: .object(object)
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    func fetchUsage(
        authJSON: JSONValue,
        clientFallback: JSONValue? = nil,
        expectedEmail: String? = nil
    ) async throws -> (authJSON: JSONValue, usage: UsageSnapshot, planType: String?) {
        // Kept only for source compatibility while call sites migrate. Never
        // borrow a client from another saved OAuth record.
        _ = clientFallback
        let storedEmail = Self.trimmed(expectedEmail ?? authJSON["email"]?.stringValue)
        var nativeFailure: Error?
        do {
            let native = try await loadNativeUsage(expectedEmail: storedEmail.isEmpty ? nil : storedEmail)
            return (authJSON, native.usage, native.planType)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Native-session markers deliberately carry no portable credentials.
            // Do not attribute a different saved OAuth token to that session.
            if authJSON["native_session"]?.boolValue == true {
                throw error
            }
            nativeFailure = error
        }

        guard !Self.trimmed(authJSON["refresh_token"]?.stringValue).isEmpty
                || !Self.trimmed(authJSON["access_token"]?.stringValue).isEmpty
        else {
            throw nativeFailure ?? AppError.unauthorized(L10n.tr("error.antigravity.native_session_unavailable"))
        }

        var refreshedAuth = try await prepareStoredCredentialForUse(authJSON)
        guard let profile = AntigravityOAuthProfile.resolve(from: refreshedAuth) else {
            throw AppError.unauthorized(L10n.tr("error.antigravity.native_oauth_profile_unavailable"))
        }
        var accessToken = Self.trimmed(refreshedAuth["access_token"]?.stringValue)
        guard !accessToken.isEmpty else {
            throw AppError.unauthorized(L10n.tr("error.accounts.sign_in_expired"))
        }

        do {
            let result = try await loadRemoteUsage(
                accessToken: accessToken,
                authJSON: refreshedAuth,
                profile: profile
            )
            return (refreshedAuth, result.usage, result.planType)
        } catch is CancellationError {
            throw CancellationError()
        } catch let firstError {
            guard Self.isAuthenticationFailure(firstError),
                  !Self.trimmed(refreshedAuth["refresh_token"]?.stringValue).isEmpty
            else {
                throw AntigravityCredentialRefreshFailure(
                    verifiedAuthJSON: refreshedAuth,
                    underlying: firstError
                )
            }

            do {
                refreshedAuth = try await refreshAccessToken(refreshedAuth, profile: profile)
                refreshedAuth = try await bindStoredCredentialIdentity(refreshedAuth, profile: profile)
                accessToken = Self.trimmed(refreshedAuth["access_token"]?.stringValue)
                guard !accessToken.isEmpty else {
                    throw AppError.unauthorized(L10n.tr("error.accounts.sign_in_expired"))
                }
                let result = try await loadRemoteUsage(
                    accessToken: accessToken,
                    authJSON: refreshedAuth,
                    profile: profile
                )
                return (refreshedAuth, result.usage, result.planType)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw AntigravityCredentialRefreshFailure(
                    verifiedAuthJSON: refreshedAuth,
                    underlying: error
                )
            }
        }
    }

    /// Direct native-status callers must receive a stable, non-secret-bearing
    /// error category even when a loopback transport implementation throws a
    /// platform-specific error.
    private func loadNativeUsage(expectedEmail: String?) async throws -> AntigravityNativeUsageResult {
        do {
            return try await nativeUsageService.fetchCurrentUsage(expectedEmail: expectedEmail)
        } catch let error as CancellationError {
            throw error
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.network(L10n.tr("error.antigravity.native_session_unavailable"))
        }
    }

    /// This mapper is intentionally quota-only. It does not infer a plan from
    /// model names and it does not assign model data to invented time windows.
    static func mapModels(_ models: [String: JSONValue], fetchedAt: Int64) -> UsageSnapshot {
        let buckets = models.keys.sorted().compactMap { modelID -> UsageQuotaBucket? in
            guard let quota = quota(from: models[modelID]) else { return nil }
            guard quota.remaining.isFinite, (0...1).contains(quota.remaining) else { return nil }
            return UsageQuotaBucket(
                id: modelID,
                displayName: modelID,
                usedPercent: (1 - quota.remaining) * 100,
                resetAt: quota.resetAt,
                windowSeconds: nil,
                resetDescription: nil,
                isUsageKnown: true
            )
        }
        return UsageSnapshot(
            fetchedAt: fetchedAt,
            planType: nil,
            fiveHour: nil,
            oneWeek: nil,
            credits: nil,
            quotaFamilies: buckets.isEmpty ? nil : [
                UsageQuotaFamily(
                    id: "remote-models",
                    displayName: "Remote verified models",
                    buckets: buckets
                )
            ],
            source: .antigravityRemoteQuota,
            sourceAccountMatched: false
        )
    }

    /// Model names describe capabilities, not subscription tiers.
    static func inferredPlanType(from models: [String: JSONValue]) -> String? {
        _ = models
        return nil
    }

    static func normalizedPlanType(from value: String?) -> String? {
        let normalized = trimmed(value).lowercased()
        if normalized.contains("ultra") { return "ultra" }
        if normalized.contains("pro") { return "pro" }
        if normalized.contains("free") { return "free" }
        return nil
    }

    private func fetchGoogleUserInfoEmail(accessToken: String) async throws -> String {
        guard let url = URL(string: "https://openidconnect.googleapis.com/v1/userinfo") else {
            throw AppError.network(L10n.tr("error.antigravity.native_identity_unavailable"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await userInfoLoader(request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.unauthorized(L10n.tr("error.antigravity.native_identity_unavailable"))
        }
        let payload: JSONValue
        do {
            payload = try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_identity_unavailable"))
        }
        if payload["email_verified"]?.boolValue == false || payload["verified_email"]?.boolValue == false {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_identity_unavailable"))
        }
        guard let email = Self.normalizedEmail(payload["email"]?.stringValue) else {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_identity_unavailable"))
        }
        return email
    }

    private struct RemoteQuotaContext: Sendable {
        var profile: AntigravityOAuthProfile
        var baseURL: String
        var explicitProjectID: String?

        /// Native GCP mode may use a caller-provided provider project. Parsed
        /// quota projects are never echoed as a billing header.
        var sendsExplicitUserProjectHeader: Bool {
            profile == .gcp && explicitProjectID != nil
        }
    }

    /// Binds a saved credential to its declared profile and its own identity.
    /// Unbound historic raw tokens must refresh once with the exact profile
    /// client before they receive the portable-native marker.
    private func prepareStoredCredentialForUse(
        _ authJSON: JSONValue,
        forceRefresh: Bool = false
    ) async throws -> JSONValue {
        guard authJSON["native_session"]?.boolValue != true,
              AntigravityAuthRepository.looksLikeGeminiOAuth(authJSON),
              let profile = AntigravityOAuthProfile.resolve(from: authJSON)
        else {
            throw AppError.unauthorized(L10n.tr("error.antigravity.native_oauth_profile_unavailable"))
        }
        var refreshed = authJSON
        if forceRefresh
            || Self.accessTokenNeedsRefresh(in: refreshed)
            || !AntigravityOAuthProfile.hasRefreshVerifiedBinding(refreshed) {
            refreshed = try await refreshAccessToken(refreshed, profile: profile)
        }
        return try await bindStoredCredentialIdentity(refreshed, profile: profile)
    }

    private func bindStoredCredentialIdentity(
        _ authJSON: JSONValue,
        profile: AntigravityOAuthProfile
    ) async throws -> JSONValue {
        guard var object = authJSON.objectValue,
              let expectedEmail = Self.normalizedEmail(
                object["email"]?.stringValue
                    ?? AntigravityOAuthSnapshotCodec.emailFromIDToken(object["id_token"]?.stringValue)
              )
        else {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_identity_unavailable"))
        }
        let accessToken = Self.trimmed(object["access_token"]?.stringValue)
        guard !accessToken.isEmpty else {
            throw AppError.unauthorized(L10n.tr("error.accounts.sign_in_expired"))
        }
        let actualEmail = try await fetchGoogleUserInfoEmail(accessToken: accessToken)
        guard Self.normalizedEmail(actualEmail) == expectedEmail else {
            throw AppError.invalidData(L10n.tr("error.antigravity.native_session_mismatch"))
        }

        object = profile.binding(object, verifiedAt: dateProvider.unixSecondsNow())
        object["email"] = .string(actualEmail)
        object["antigravity_native_credential"] = .bool(true)
        object["antigravity_native_credential_origin"] = .string("profile-refresh-userinfo")
        object["antigravity_native_credential_email"] = .string(actualEmail)
        object["antigravity_native_credential_verified_at"] = .number(
            Double(dateProvider.unixSecondsNow())
        )
        return .object(object)
    }

    private func remoteQuotaContext(
        authJSON: JSONValue,
        profile: AntigravityOAuthProfile
    ) -> RemoteQuotaContext {
        RemoteQuotaContext(
            profile: profile,
            baseURL: AntigravityOAuthProfile.configuredCloudCodeBaseURL(
                from: authJSON,
                profile: profile
            ),
            explicitProjectID: AntigravityOAuthProfile.explicitProviderProjectID(from: authJSON)
        )
    }

    private func loadRemoteUsage(
        accessToken: String,
        authJSON: JSONValue,
        profile: AntigravityOAuthProfile
    ) async throws -> (usage: UsageSnapshot, planType: String?) {
        let context = remoteQuotaContext(authJSON: authJSON, profile: profile)
        var codeAssist = try await loadCodeAssist(
            accessToken: accessToken,
            context: context,
            projectID: context.explicitProjectID
        )
        var quotaProjectID = Self.cloudCodeProjectID(from: codeAssist) ?? context.explicitProjectID

        // Native does a project-qualified second load only when the first
        // response has no paid tier. This is distinct from a model probe and
        // gives retrieveUserQuotaSummary the target account's own project.
        if !Self.hasPaidTier(codeAssist), let projectID = quotaProjectID {
            codeAssist = try await loadCodeAssist(
                accessToken: accessToken,
                context: context,
                projectID: projectID
            )
            quotaProjectID = Self.cloudCodeProjectID(from: codeAssist) ?? projectID
        }
        guard let quotaProjectID, !quotaProjectID.isEmpty else {
            throw AppError.network(L10n.tr("error.antigravity.remote_quota_unavailable"))
        }

        let quotaPayload = try await retrieveUserQuotaSummary(
            accessToken: accessToken,
            context: context,
            projectID: quotaProjectID
        )
        let planType = Self.planType(fromCodeAssist: codeAssist)
        let usage = try AntigravityNativeUsageService.usageSnapshot(
            fromQuotaSummary: quotaPayload,
            fetchedAt: dateProvider.unixSecondsNow(),
            planType: planType,
            source: .antigravityRemoteQuota,
            sourceAccountMatched: true
        )
        return (usage, planType)
    }

    private static func planType(fromCodeAssist payload: JSONValue) -> String? {
        let payload = payload["response"] ?? payload
        let paidFields = [
            payload["paidTier"]?["id"]?.stringValue,
            payload["paidTier"]?["name"]?.stringValue,
            payload["paidTier"]?["preferredName"]?.stringValue
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        if let paid = normalizedPlanType(from: paidFields), paid != "free" {
            return paid
        }
        let currentFields = [
            payload["currentTier"]?["id"]?.stringValue,
            payload["currentTier"]?["name"]?.stringValue,
            payload["currentTier"]?["preferredName"]?.stringValue
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        // Missing/ambiguous current tiers stay unknown, never free.
        return normalizedPlanType(from: currentFields)
    }

    private func refreshAccessToken(
        _ authJSON: JSONValue,
        profile: AntigravityOAuthProfile
    ) async throws -> JSONValue {
        guard var object = authJSON.objectValue,
              AntigravityOAuthProfile.resolve(from: authJSON) == profile
        else {
            throw AppError.unauthorized(L10n.tr("error.antigravity.native_oauth_profile_unavailable"))
        }
        let refreshToken = Self.trimmed(object["refresh_token"]?.stringValue)
        guard !refreshToken.isEmpty else {
            throw AppError.unauthorized(L10n.tr("error.antigravity.missing_refresh_token"))
        }
        let client: AntigravityOAuthClientCredentials
        do {
            client = try oauthCredentialResolver(profile)
        } catch {
            throw AppError.unauthorized(L10n.tr("error.antigravity.native_oauth_profile_unavailable"))
        }
        guard client.clientID == profile.publicClientID,
              !client.clientSecret.isEmpty
        else {
            throw AppError.unauthorized(L10n.tr("error.antigravity.native_oauth_profile_unavailable"))
        }
        let payload = try await requestRefreshedToken(
            clientID: client.clientID,
            clientSecret: client.clientSecret,
            refreshToken: refreshToken
        )
        let access = Self.trimmed(payload["access_token"]?.stringValue)
        guard !access.isEmpty,
              let expiresIn = Self.number(payload["expires_in"]),
              expiresIn.isFinite,
              expiresIn > 0
        else {
            throw AppError.unauthorized(L10n.tr("error.accounts.sign_in_expired"))
        }
        object["access_token"] = .string(access)
        // Google may omit a refresh token during a normal renewal. Preserve
        // the account's old grant unless a rotated replacement was supplied.
        if let refresh = payload["refresh_token"],
           !Self.trimmed(refresh.stringValue).isEmpty {
            object["refresh_token"] = refresh
        }
        if let idToken = payload["id_token"], !Self.trimmed(idToken.stringValue).isEmpty {
            object["id_token"] = idToken
        }
        if let tokenType = payload["token_type"], !Self.trimmed(tokenType.stringValue).isEmpty {
            object["token_type"] = tokenType
        }
        let expiry = Date().addingTimeInterval(expiresIn)
        object["expires_in"] = .number(expiresIn)
        object["expiry_date"] = .number(expiry.timeIntervalSince1970 * 1_000)
        object["expiry"] = .string(Self.rfc3339Timestamp(for: expiry))
        return .object(profile.binding(object))
    }

    private func requestRefreshedToken(
        clientID: String,
        clientSecret: String,
        refreshToken: String
    ) async throws -> JSONValue {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let pieces = [
            "client_id=\(urlEncode(clientID))",
            "client_secret=\(urlEncode(clientSecret))",
            "refresh_token=\(urlEncode(refreshToken))",
            "grant_type=refresh_token"
        ]
        request.httpBody = pieces.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AppError.unauthorized(L10n.tr("error.accounts.sign_in_expired"))
        }
        return try JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func retrieveUserQuotaSummary(
        accessToken: String,
        context: RemoteQuotaContext,
        projectID: String
    ) async throws -> JSONValue {
        try await requestCloudCode(
            path: "retrieveUserQuotaSummary",
            accessToken: accessToken,
            context: context,
            body: .object(["project": .string(projectID)])
        )
    }

    private func loadCodeAssist(
        accessToken: String,
        context: RemoteQuotaContext,
        projectID: String?
    ) async throws -> JSONValue {
        var body: [String: JSONValue] = [
            "metadata": .object(["ideType": .string("ANTIGRAVITY")])
        ]
        if let projectID, !projectID.isEmpty {
            body["cloudaicompanionProject"] = .string(projectID)
        }
        return try await requestCloudCode(
            path: "loadCodeAssist",
            accessToken: accessToken,
            context: context,
            body: .object(body)
        )
    }

    private func requestCloudCode(
        path: String,
        accessToken: String,
        context: RemoteQuotaContext,
        body: JSONValue
    ) async throws -> JSONValue {
        guard let url = URL(string: "\(context.baseURL)\(path)") else {
            throw AppError.network(L10n.tr("error.antigravity.remote_quota_unavailable"))
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "antigravity/hub/2.12.2 (os_type=darwin; arch=arm64)",
            forHTTPHeaderField: "User-Agent"
        )
        if context.sendsExplicitUserProjectHeader,
           let projectID = context.explicitProjectID {
            request.setValue(projectID, forHTTPHeaderField: "X-Goog-User-Project")
        }
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppError.network(L10n.tr("error.antigravity.remote_quota_unavailable"))
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 {
                throw AppError.unauthorized(L10n.tr("error.accounts.sign_in_expired"))
            }
            throw AppError.network(L10n.tr("error.antigravity.remote_quota_unavailable"))
        }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw AppError.network(L10n.tr("error.antigravity.remote_quota_unavailable"))
        }
    }

    private static func cloudCodeProjectID(from payload: JSONValue) -> String? {
        let candidates = [
            payload["cloudaicompanionProject"]?.stringValue,
            payload["response"]?["cloudaicompanionProject"]?.stringValue,
            payload["result"]?["cloudaicompanionProject"]?.stringValue
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
    }

    private static func hasPaidTier(_ payload: JSONValue) -> Bool {
        let value = payload["paidTier"] ?? payload["response"]?["paidTier"]
        return value?.objectValue != nil
    }

    private static func decodeModels(_ payload: JSONValue) -> [String: JSONValue]? {
        if let models = payload["models"]?.objectValue, !models.isEmpty { return models }
        if let models = payload["response"]?["models"]?.objectValue, !models.isEmpty { return models }
        if let models = payload["result"]?["models"]?.objectValue, !models.isEmpty { return models }
        let rawBuckets = payload["buckets"]?.arrayValue ?? payload["response"]?["buckets"]?.arrayValue ?? []
        var mapped: [String: JSONValue] = [:]
        for (index, item) in rawBuckets.enumerated() {
            let candidate = item["model"]?.stringValue ?? item["modelId"]?.stringValue ?? item["bucketId"]?.stringValue
            mapped[(candidate?.isEmpty == false ? candidate! : "bucket-\(index)")] = item
        }
        return mapped.isEmpty ? nil : mapped
    }

    private static func quota(from model: JSONValue?) -> (remaining: Double, resetAt: Int64?)? {
        guard let model else { return nil }
        let info = model["quotaInfo"] ?? model
        guard let remaining = number(info["remainingFraction"] ?? info["remaining"]?["remainingFraction"]) else {
            return nil
        }
        return (remaining, parseReset(info["resetTime"]?.stringValue))
    }

    private static func number(_ value: JSONValue?) -> Double? {
        if let value = value?.doubleValue { return value }
        if let value = value?.stringValue, let number = Double(value) { return number }
        return nil
    }

    private static func parseReset(_ value: String?) -> Int64? {
        let value = trimmed(value)
        guard !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return Int64(date.timeIntervalSince1970) }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: value) { return Int64(date.timeIntervalSince1970) }
        return nil
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func normalizedEmail(_ value: String?) -> String? {
        let value = trimmed(value).lowercased()
        return value.contains("@") ? value : nil
    }

    private static func accessTokenNeedsRefresh(in authJSON: JSONValue) -> Bool {
        // OAuth access tokens are refreshed five minutes early. An absent or
        // malformed expiry is not assumed fresh; a profile-bound refresh is
        // safer than staging a token whose lifetime cannot be established.
        guard let seconds = accessTokenExpirySeconds(in: authJSON) else { return true }
        return seconds <= Date().timeIntervalSince1970 + 300
    }

    private static func accessTokenExpirySeconds(in authJSON: JSONValue) -> Double? {
        for key in ["expiry_date", "expiryDate", "expiry"] {
            if let numeric = authJSON[key]?.doubleValue, numeric.isFinite, numeric > 0 {
                return numeric > 10_000_000_000 ? numeric / 1_000 : numeric
            }
            guard let text = authJSON[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty
            else { continue }
            if let numeric = Double(text), numeric.isFinite, numeric > 0 {
                return numeric > 10_000_000_000 ? numeric / 1_000 : numeric
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) {
                return date.timeIntervalSince1970
            }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            if let date = plain.date(from: text) {
                return date.timeIntervalSince1970
            }
        }
        return nil
    }

    private static func rfc3339Timestamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func isAuthenticationFailure(_ error: Error) -> Bool {
        if case .unauthorized = error as? AppError {
            return true
        }
        let message = error.localizedDescription.lowercased()
        return message.contains("http 401")
            || message.contains("unauthorized")
            || message.contains("invalid authentication")
            || message.contains("token expired")
    }

    private func urlEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

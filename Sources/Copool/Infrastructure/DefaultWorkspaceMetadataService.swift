import Foundation
import OSLog

final class DefaultWorkspaceMetadataService: WorkspaceMetadataService, @unchecked Sendable {
    private enum RequestPolicy {
        static let timeout: TimeInterval = 18
        static let scope = "workspace-metadata"
    }

    private static let logger = Logger(subsystem: "Copool", category: "WorkspaceMetadata")

    private let session: URLSession
    private let configPath: URL
    private let endpointCoordinator: EndpointRequestCoordinator

    init(
        session: URLSession = BackgroundNetworkSession.shared,
        configPath: URL,
        endpointPreferenceStore: EndpointPreferenceStore = .shared
    ) {
        self.session = session
        self.configPath = configPath
        self.endpointCoordinator = EndpointRequestCoordinator(
            session: session,
            preferenceStore: endpointPreferenceStore
        )
    }

    func fetchWorkspaceMetadata(accessToken: String) async throws -> [WorkspaceMetadata] {
        let candidateURLs = resolveAccountURLs()
        let startedAt = Date()

        do {
            let resolved = try await fetchWorkspaceMetadataOnce(
                accessToken: accessToken,
                candidateURLs: candidateURLs
            )
            return resolved.metadata
        } catch EndpointRequestError.allRequestsFailed(let errors) {
            if errors.contains(where: Self.isHTMLForbiddenFailure) {
                Self.logger.debug("Workspace discovery hit transient HTML 403. Retrying once.")
                do {
                    let resolved = try await fetchWorkspaceMetadataOnce(
                        accessToken: accessToken,
                        candidateURLs: candidateURLs
                    )
                    return resolved.metadata
                } catch EndpointRequestError.allRequestsFailed(let retryErrors) {
                    let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
                    Self.logger.error(
                        "Workspace discovery failed after retry in \(elapsedMilliseconds) ms. Candidates: \(candidateURLs.joined(separator: " | "), privacy: .public). Errors: \(retryErrors.joined(separator: " | "), privacy: .public)"
                    )
                    if let message = Self.preferredUserFacingFailureMessage(from: retryErrors) {
                        throw AppError.network(message)
                    }
                    let preview = retryErrors.prefix(2).joined(separator: " | ")
                    if retryErrors.count > 2 {
                        throw AppError.network(L10n.tr("error.usage.request_failed_with_more_format", preview, String(retryErrors.count - 2)))
                    }
                    throw AppError.network(L10n.tr("error.usage.request_failed_format", preview))
                }
            }
            let elapsedMilliseconds = Int(Date().timeIntervalSince(startedAt) * 1_000)
            Self.logger.error(
                "Workspace discovery failed after \(elapsedMilliseconds) ms. Candidates: \(candidateURLs.joined(separator: " | "), privacy: .public). Errors: \(errors.joined(separator: " | "), privacy: .public)"
            )
            if let message = Self.preferredUserFacingFailureMessage(from: errors) {
                throw AppError.network(message)
            }
            let preview = errors.prefix(2).joined(separator: " | ")
            if errors.count > 2 {
                throw AppError.network(L10n.tr("error.usage.request_failed_with_more_format", preview, String(errors.count - 2)))
            }
            throw AppError.network(L10n.tr("error.usage.request_failed_format", preview))
        }
    }

    private func fetchWorkspaceMetadataOnce(
        accessToken: String,
        candidateURLs: [String]
    ) async throws -> ResolvedWorkspaceAccounts {
        try await endpointCoordinator.fetchFirstSuccessful(
            scope: RequestPolicy.scope,
            candidateURLs: candidateURLs
        ) { endpoint in
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = RequestPolicy.timeout
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("codex-tools-swift/0.1", forHTTPHeaderField: "User-Agent")
            return request
        } validate: { result in
            let payload = try JSONDecoder().decode(WorkspaceAccountsResponse.self, from: result.data)
            let metadata = payload.items.map {
                WorkspaceMetadata(
                    accountID: $0.id,
                    workspaceName: $0.name,
                    structure: $0.structure
                )
            }
            return ResolvedWorkspaceAccounts(
                endpoint: result.endpoint,
                metadata: metadata
            )
        }
    }

    private static func preferredUserFacingFailureMessage(from errors: [String]) -> String? {
        for error in errors {
            let detail = error.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
            guard let detail = detail.nonEmptyTrimmed,
                  !detail.hasPrefix("<"),
                  !isCancellationFailure(error),
                  !isTimeoutFailure(error) else {
                continue
            }
            return detail
        }

        if errors.contains(where: isCancellationFailure) {
            return L10n.tr("error.workspace.discovery_cancelled")
        }
        if errors.contains(where: isTimeoutFailure) {
            return L10n.tr("error.workspace.discovery_timed_out")
        }
        if errors.contains(where: isHTMLForbiddenFailure) {
            return L10n.tr("error.workspace.discovery_forbidden")
        }
        return nil
    }

    private static func isCancellationFailure(_ error: String) -> Bool {
        error.lowercased().contains("cancelled")
    }

    private static func isTimeoutFailure(_ error: String) -> Bool {
        let normalized = error.lowercased()
        return normalized.contains("timed out") || normalized.contains("timeout")
    }

    private static func isHTMLForbiddenFailure(_ error: String) -> Bool {
        let normalized = error.lowercased()
        let containsHTML = normalized.contains("<html") || normalized.contains("<head") || normalized.contains("<meta ")
        return containsHTML && normalized.contains("-> 403:")
    }

    private func resolveAccountURLs() -> [String] {
        let baseOrigin = ChatGPTBaseOriginResolver.resolve(configPath: configPath)
        let backendPrefix = "/backend-api"

        var candidates: [String] = []
        if let originWithoutBackend = baseOrigin.removingSuffix(backendPrefix) {
            candidates.append("\(baseOrigin)/accounts")
            candidates.append("\(originWithoutBackend)\(backendPrefix)/accounts")
        } else {
            candidates.append("\(baseOrigin)\(backendPrefix)/accounts")
        }

        candidates.append("https://chatgpt.com/backend-api/accounts")

        var deduped: [String] = []
        for candidate in candidates where !deduped.contains(candidate) {
            deduped.append(candidate)
        }
        return deduped
    }

    private static func requestLogSummary(for request: URLRequest) -> String {
        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? ""
        let headers = (request.allHTTPHeaderFields ?? [:])
            .filter { $0.key.caseInsensitiveCompare("Authorization") != .orderedSame }
        let payload: [String: Any] = [
            "method": method,
            "url": url,
            "headers": headers
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "\(method) \(url)"
        }
        return text
    }

    private static func responseLogBody(for data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "<non-utf8 body: \(data.count) bytes>"
    }
}

private struct WorkspaceAccountsResponse: Decodable {
    var items: [WorkspaceAccountItem]
}

private struct ResolvedWorkspaceAccounts: Sendable {
    var endpoint: String
    var metadata: [WorkspaceMetadata]
}

private struct WorkspaceAccountItem: Decodable {
    var id: String
    var name: String?
    var structure: String?
}

private extension String {
    func removingSuffix(_ suffix: String) -> String? {
        guard hasSuffix(suffix) else { return nil }
        return String(dropLast(suffix.count))
    }

    var nonEmptyTrimmed: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#if DEBUG
extension DefaultWorkspaceMetadataService {
    static func debugPreferredUserFacingFailureMessage(from errors: [String]) -> String? {
        preferredUserFacingFailureMessage(from: errors)
    }

    static func debugRequestLogSummary(for request: URLRequest) -> String {
        requestLogSummary(for: request)
    }

    static func debugResponseLogBody(for data: Data) -> String {
        responseLogBody(for: data)
    }
}
#endif

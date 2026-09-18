import Foundation

actor EndpointPreferenceStore {
    static let shared = EndpointPreferenceStore()

    private var preferredEndpointByScope: [String: String] = [:]

    func prioritizedCandidates(scope: String, candidates: [String]) -> [String] {
        guard let preferred = preferredEndpointByScope[scope],
              candidates.contains(preferred) else {
            return candidates
        }

        return [preferred] + candidates.filter { $0 != preferred }
    }

    func recordSuccess(scope: String, endpoint: String) {
        preferredEndpointByScope[scope] = endpoint
    }
}

struct EndpointFetchResult: Sendable {
    let data: Data
    let response: HTTPURLResponse
    let endpoint: String
}

enum EndpointRequestError: Error {
    case allRequestsFailed([String])
}

final class EndpointRequestCoordinator: @unchecked Sendable {
    private let session: URLSession
    private let preferenceStore: EndpointPreferenceStore

    init(
        session: URLSession,
        preferenceStore: EndpointPreferenceStore = .shared
    ) {
        self.session = session
        self.preferenceStore = preferenceStore
    }

    func fetchFirstSuccessful(
        scope: String,
        candidateURLs: [String],
        makeRequest: @escaping @Sendable (URL) -> URLRequest
    ) async throws -> EndpointFetchResult {
        try await fetchFirstSuccessful(
            scope: scope,
            candidateURLs: candidateURLs,
            makeRequest: makeRequest,
            validate: { $0 }
        )
    }

    func fetchFirstSuccessful<Value: Sendable>(
        scope: String,
        candidateURLs: [String],
        makeRequest: @escaping @Sendable (URL) -> URLRequest,
        validate: @escaping @Sendable (EndpointFetchResult) throws -> Value
    ) async throws -> Value {
        let orderedCandidates = await preferenceStore.prioritizedCandidates(
            scope: scope,
            candidates: candidateURLs
        )
        guard let firstCandidate = orderedCandidates.first else {
            throw EndpointRequestError.allRequestsFailed([])
        }

        var failures: [String] = []

        switch await attemptRequest(
            endpointString: firstCandidate,
            makeRequest: makeRequest,
            validate: validate
        ) {
        case .success(let result):
            await preferenceStore.recordSuccess(scope: scope, endpoint: result.endpoint)
            return result.value
        case .failure(let message):
            failures.append(message)
        }

        let remainingCandidates = Array(orderedCandidates.dropFirst())
        guard !remainingCandidates.isEmpty else {
            throw EndpointRequestError.allRequestsFailed(failures)
        }

        let result = await withTaskGroup(
            of: AttemptResult<Value>.self,
            returning: ValidatedEndpointFetchResult<Value>?.self
        ) { group in
            for endpointString in remainingCandidates {
                group.addTask { [session] in
                    await Self.attemptRequest(
                        session: session,
                        endpointString: endpointString,
                        makeRequest: makeRequest,
                        validate: validate
                    )
                }
            }

            for await outcome in group {
                switch outcome {
                case .success(let value):
                    group.cancelAll()
                    return value
                case .failure(let message):
                    failures.append(message)
                }
            }

            return nil
        }

        guard let result else {
            throw EndpointRequestError.allRequestsFailed(failures)
        }

        await preferenceStore.recordSuccess(scope: scope, endpoint: result.endpoint)
        return result.value
    }

    private func attemptRequest<Value: Sendable>(
        endpointString: String,
        makeRequest: @escaping @Sendable (URL) -> URLRequest,
        validate: @escaping @Sendable (EndpointFetchResult) throws -> Value
    ) async -> AttemptResult<Value> {
        await Self.attemptRequest(
            session: session,
            endpointString: endpointString,
            makeRequest: makeRequest,
            validate: validate
        )
    }

    private static func attemptRequest<Value: Sendable>(
        session: URLSession,
        endpointString: String,
        makeRequest: @escaping @Sendable (URL) -> URLRequest,
        validate: @escaping @Sendable (EndpointFetchResult) throws -> Value
    ) async -> AttemptResult<Value> {
        guard let endpoint = URL(string: endpointString) else {
            return .failure("\(endpointString) -> invalid URL")
        }

        do {
            let (data, response) = try await session.data(for: makeRequest(endpoint))
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure("\(endpointString) -> invalid response")
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                let detail = OpenAIChatGPTOAuthSupport.bestHTTPErrorMessage(
                    from: data,
                    statusCode: httpResponse.statusCode,
                    snippetLimit: 140
                )
                return .failure("\(endpointString) -> \(httpResponse.statusCode): \(detail)")
            }

            let result = EndpointFetchResult(
                data: data,
                response: httpResponse,
                endpoint: endpointString
            )

            do {
                let validated = try validate(result)
                return .success(
                    ValidatedEndpointFetchResult(
                        value: validated,
                        endpoint: endpointString
                    )
                )
            } catch {
                return .failure("\(endpointString) -> \(error.localizedDescription)")
            }
        } catch {
            return .failure("\(endpointString) -> \(error.localizedDescription)")
        }
    }

    private struct ValidatedEndpointFetchResult<Value: Sendable>: Sendable {
        let value: Value
        let endpoint: String
    }

    private enum AttemptResult<Value: Sendable>: Sendable {
        case success(ValidatedEndpointFetchResult<Value>)
        case failure(String)
    }
}

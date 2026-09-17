import Foundation
import CryptoKit

enum OpenAIChatGPTOAuthSupport {
    static func extractAccountID(fromIDToken idToken: String) throws -> String {
        let payload = try AuthJWTDecoder.decodePayload(idToken)
        guard let accountID = payload["https://api.openai.com/auth"]?["chatgpt_account_id"]?.stringValue,
              !accountID.isEmpty else {
            throw AppError.invalidData(L10n.tr("error.auth.missing_chatgpt_account_id"))
        }
        return accountID
    }

    static func formEncodedBody(_ items: [(String, String)]) -> Data {
        let encoded = items
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }

    static func randomBase64URL(byteCount: Int) -> String {
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max) }
        let data = Data(bytes)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func successPageHTML() -> Data {
        Data(
            """
            <html>
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>AILSA SubSwitch</title>
            </head>
            <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;">
            <h2>Finishing sign-in</h2>
            <p>AILSA SubSwitch is completing the authorization. You can return to the app now.</p>
            <script>
            (function () {
              function tryClose() {
                window.open('', '_self');
                window.close();
              }
              setTimeout(tryClose, 120);
              setTimeout(tryClose, 600);
              setTimeout(tryClose, 1200);
            })();
            </script>
            </body>
            </html>
            """.utf8
        )
    }

    static func errorPageHTML(message: String) -> Data {
        let escapedMessage = htmlEscape(message)
        return Data("<html><head><meta charset=\"utf-8\"><title>AILSA SubSwitch</title></head><body style=\"font-family:-apple-system,BlinkMacSystemFont,sans-serif;padding:32px;\"><h2>Sign-in failed</h2><p>\(escapedMessage)</p></body></html>".utf8)
    }

    static func bestHTTPErrorMessage(
        from data: Data,
        statusCode: Int? = nil,
        snippetLimit: Int = 200
    ) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = object["error"] as? [String: Any],
               let message = normalizedMessage(error["message"] as? String) {
                return message
            }

            if let errors = object["errors"] as? [[String: Any]],
               let message = errors.lazy.compactMap({ normalizedMessage($0["message"] as? String) }).first {
                return message
            }

            if let description = normalizedMessage(object["error_description"] as? String) {
                return description
            }

            if let error = normalizedMessage(object["error"] as? String) {
                return error
            }
        }

        if let body = normalizedMessage(String(data: data, encoding: .utf8)) {
            return String(body.prefix(snippetLimit))
        }

        if let statusCode {
            return "HTTP \(statusCode)"
        }

        return L10n.tr("error.usage.invalid_response")
    }

    private static func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .oauthFormAllowed) ?? value
    }

    private static func htmlEscape(_ value: String) -> String {
        var escaped = value
        let mappings = [
            ("&", "&amp;"),
            ("<", "&lt;"),
            (">", "&gt;"),
            ("\"", "&quot;"),
            ("'", "&#39;")
        ]
        for (source, target) in mappings {
            escaped = escaped.replacingOccurrences(of: source, with: target)
        }
        return escaped
    }

    private static func normalizedMessage(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct PKCECodes {
    var codeVerifier: String
    var codeChallenge: String

    static func make() -> PKCECodes {
        let verifier = OpenAIChatGPTOAuthSupport.randomBase64URL(byteCount: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return PKCECodes(codeVerifier: verifier, codeChallenge: challenge)
    }
}

final class OAuthCallbackBox<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, any Error>?
    private var result: Result<Value, AppError>?

    func wait(
        timeoutSeconds: TimeInterval,
        timeoutError: @escaping @Sendable () -> AppError,
        cancelError: @escaping @Sendable () -> AppError
    ) async throws -> Value {
        let timeoutTask = Task { [weak self] in
            let nanoseconds = UInt64(max(timeoutSeconds, 0) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            self?.fail(timeoutError())
        }
        defer { timeoutTask.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Value, any Error>) in
                lock.lock()
                if let result {
                    lock.unlock()
                    resume(continuation, with: result)
                    return
                }
                self.continuation = continuation
                lock.unlock()
            }
        } onCancel: { [weak self] in
            self?.fail(cancelError())
        }
    }

    func succeed(_ value: Value) {
        resolve(.success(value))
    }

    func fail(_ error: Error) {
        resolve(.failure(Self.normalize(error)))
    }

    private func resolve(_ result: Result<Value, AppError>) {
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return
        }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        if let continuation {
            resume(continuation, with: result)
        }
    }

    private func resume(_ continuation: CheckedContinuation<Value, any Error>, with result: Result<Value, AppError>) {
        switch result {
        case .success(let value):
            continuation.resume(returning: value)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private static func normalize(_ error: Error) -> AppError {
        if let appError = error as? AppError {
            return appError
        }
        return .io(error.localizedDescription)
    }
}

struct TokenExchangeResponse: Decodable {
    let idToken: String
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

struct APIKeyExchangeResponse: Decodable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

struct RefreshedChatGPTOAuthTokenResponse: Decodable {
    let idToken: String
    let accessToken: String
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
    }
}

private extension CharacterSet {
    static let oauthFormAllowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}

extension HTTPResponse {
    static func html(statusCode: Int, body: Data) -> HTTPResponse {
        HTTPResponse(
            statusCode: statusCode,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: body
        )
    }
}

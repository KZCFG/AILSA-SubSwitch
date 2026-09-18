import Foundation

enum AuthJWTDecoder {
    static func tokenObject(from auth: JSONValue) -> [String: JSONValue]? {
        if let tokens = auth["tokens"]?.objectValue {
            return tokens
        }

        if let object = auth.objectValue,
           object["access_token"]?.stringValue != nil,
           object["id_token"]?.stringValue != nil {
            return object
        }

        return nil
    }

    static func decodePayload(_ token: String) throws -> JSONValue {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count > 1 else {
            throw AppError.invalidData(L10n.tr("error.auth.id_token_invalid_format"))
        }

        let payload = String(segments[1])
        let data = try decodeBase64URL(payload)
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONValue.from(any: object)
    }

    private static func decodeBase64URL(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: base64) else {
            throw AppError.invalidData(L10n.tr("error.auth.decode_id_token_failed"))
        }
        return data
    }
}

enum AuthPrincipalIDResolver {
    static func resolve(
        from auth: JSONValue,
        claims: JSONValue?,
        email: String?,
        accountID: String?,
        fallbackPrincipalID: String? = nil
    ) -> String? {
        let candidates: [String?] = [
            fallbackPrincipalID,
            AuthValueLookup.string(atPath: ["tokens", "principal_id"], in: auth),
            AuthValueLookup.string(atPath: ["principal_id"], in: auth),
            AuthValueLookup.string(atPath: ["sub"], in: claims),
            AuthValueLookup.string(atPath: ["https://api.openai.com/auth", "chatgpt_user_id"], in: claims),
            AuthValueLookup.string(atPath: ["https://api.openai.com/auth", "user_id"], in: claims),
            AuthValueLookup.string(atPath: ["user", "id"], in: claims),
            AuthValueLookup.string(atPath: ["user_id"], in: claims),
            AuthValueLookup.string(atPath: ["sub"], in: auth),
            AuthValueLookup.string(atPath: ["user", "id"], in: auth),
            AuthValueLookup.string(atPath: ["user_id"], in: auth)
        ]

        for candidate in candidates {
            if let normalized = AuthValueLookup.normalizedString(candidate) {
                return AccountIdentity.normalizedPrincipalID(
                    normalized,
                    email: email,
                    accountID: accountID ?? ""
                )
            }
        }

        guard let normalizedAccountID = AuthValueLookup.normalizedString(accountID) else {
            return nil
        }
        return AccountIdentity.normalizedPrincipalID(
            nil,
            email: email,
            accountID: normalizedAccountID
        )
    }
}

enum AuthValueLookup {
    static func string(atPath path: [String], in root: JSONValue?) -> String? {
        guard let root else { return nil }
        var current = root
        for key in path {
            guard let next = current[key] else { return nil }
            current = next
        }
        return current.stringValue
    }

    static func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

import Foundation

enum AuthWorkspaceMetadataExtractor {
    static func extractTeamName(from auth: JSONValue, claims: JSONValue?, accountIDHint: String?) -> String? {
        let preferredIDs = preferredWorkspaceIDs(from: auth, claims: claims, accountIDHint: accountIDHint)

        if let fromContainers = extractNameFromContainers(
            in: claims,
            preferredIDs: preferredIDs,
            allowPersonalFallback: false
        ) ?? extractNameFromContainers(
            in: auth,
            preferredIDs: preferredIDs,
            allowPersonalFallback: false
        ) {
            return fromContainers
        }

        let claimPaths: [[String]] = [
            ["https://api.openai.com/auth", "chatgpt_team_name"],
            ["https://api.openai.com/auth", "chatgpt_workspace_slug"],
            ["https://api.openai.com/auth", "workspace_slug"],
            ["https://api.openai.com/auth", "team_slug"],
            ["https://api.openai.com/auth", "organization_slug"],
            ["https://api.openai.com/auth", "chatgpt_org_name"],
            ["https://api.openai.com/auth", "organization_name"],
            ["https://api.openai.com/auth", "org_name"],
            ["https://api.openai.com/auth", "team_name"],
            ["organization", "name"],
            ["org", "name"],
            ["team", "name"],
            ["workspace", "name"]
        ]

        for path in claimPaths {
            if let value = normalizedTeamName(AuthValueLookup.string(atPath: path, in: claims), allowPersonal: false) {
                return value
            }
        }

        let authPaths: [[String]] = [
            ["tokens", "workspace_slug"],
            ["tokens", "team_slug"],
            ["tokens", "organization_slug"],
            ["organization", "name"],
            ["org", "name"],
            ["team", "name"],
            ["workspace", "name"],
            ["tokens", "organization_name"],
            ["tokens", "org_name"],
            ["tokens", "team_name"]
        ]

        for path in authPaths {
            if let value = normalizedTeamName(AuthValueLookup.string(atPath: path, in: auth), allowPersonal: false) {
                return value
            }
        }

        let keyCandidates: Set<String> = [
            "teamname",
            "organizationname",
            "orgname",
            "workspacename",
            "tenantname",
            "displayname"
        ]

        return findFirstString(in: claims, candidateKeys: keyCandidates, allowPersonal: false)
            ?? findFirstString(in: auth, candidateKeys: keyCandidates, allowPersonal: false)
    }

    private struct WorkspaceCandidate {
        let id: String?
        let displayName: String?
        let isDefault: Bool
        let isCurrent: Bool
        let isActive: Bool
    }

    private static func normalizedTeamName(_ value: String?, allowPersonal: Bool) -> String? {
        guard let normalized = AuthValueLookup.normalizedString(value) else { return nil }
        if !allowPersonal, isPersonalName(normalized) {
            return nil
        }
        return normalized
    }

    private static func isPersonalName(_ value: String) -> Bool {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")

        return normalized == "personal"
            || normalized == "personalworkspace"
            || normalized == "myworkspace"
            || normalized == "个人"
            || normalized == "个人空间"
    }

    private static func normalizedKey(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private static func findFirstString(
        in value: JSONValue?,
        candidateKeys: Set<String>,
        allowPersonal: Bool
    ) -> String? {
        guard let value else { return nil }
        switch value {
        case .object(let object):
            for (key, item) in object {
                if candidateKeys.contains(normalizedKey(key)),
                   let match = normalizedTeamName(item.stringValue, allowPersonal: allowPersonal) {
                    return match
                }
            }
            for item in object.values {
                if let nested = findFirstString(in: item, candidateKeys: candidateKeys, allowPersonal: allowPersonal) {
                    return nested
                }
            }
            return nil
        case .array(let items):
            for item in items {
                if let nested = findFirstString(in: item, candidateKeys: candidateKeys, allowPersonal: allowPersonal) {
                    return nested
                }
            }
            return nil
        default:
            return nil
        }
    }

    private static func extractNameFromContainers(
        in root: JSONValue?,
        preferredIDs: Set<String>,
        allowPersonalFallback: Bool
    ) -> String? {
        guard let root else { return nil }
        let candidates = collectWorkspaceCandidates(in: root)
        guard !candidates.isEmpty else { return nil }

        if let matchedByID = candidates.first(where: {
            guard let id = $0.id?.lowercased() else { return false }
            return preferredIDs.contains(id)
        }), let display = normalizedTeamName(matchedByID.displayName, allowPersonal: allowPersonalFallback) {
            return display
        }

        let prioritized = candidates.sorted { lhs, rhs in
            score(candidate: lhs, preferredIDs: preferredIDs) > score(candidate: rhs, preferredIDs: preferredIDs)
        }

        for candidate in prioritized {
            if let display = normalizedTeamName(candidate.displayName, allowPersonal: false) {
                return display
            }
        }

        guard allowPersonalFallback else { return nil }
        return prioritized.compactMap { normalizedTeamName($0.displayName, allowPersonal: true) }.first
    }

    private static func score(candidate: WorkspaceCandidate, preferredIDs: Set<String>) -> Int {
        var total = 0
        if let id = candidate.id?.lowercased(), preferredIDs.contains(id) {
            total += 100
        }
        if candidate.isCurrent { total += 30 }
        if candidate.isActive { total += 20 }
        if candidate.isDefault { total += 5 }
        if let display = candidate.displayName, !isPersonalName(display) { total += 10 }
        return total
    }

    private static func collectWorkspaceCandidates(in value: JSONValue?) -> [WorkspaceCandidate] {
        guard let value else { return [] }
        switch value {
        case .object(let object):
            let containerKeys = ["organizations", "orgs", "teams", "workspaces", "groups"]
            let recursiveContainerKeys: Set<String> = [
                "https://api.openai.com/auth",
                "auth",
                "claims",
                "token",
                "tokens",
                "user",
                "profile",
                "session"
            ]
            var candidates: [WorkspaceCandidate] = []

            for key in containerKeys {
                guard let items = object[key]?.arrayValue else { continue }
                for item in items {
                    guard case .object(let obj) = item else { continue }
                    candidates.append(
                        WorkspaceCandidate(
                            id: extractString(from: obj, keys: ["id", "organization_id", "org_id", "workspace_id", "group_id"]),
                            displayName: extractString(
                                from: obj,
                                keys: ["slug", "workspace_slug", "team_slug", "organization_slug", "name", "display_name", "displayName", "title", "label"]
                            ),
                            isDefault: extractBool(from: obj, keys: ["is_default", "default"]),
                            isCurrent: extractBool(from: obj, keys: ["is_current", "current", "selected"]),
                            isActive: extractBool(from: obj, keys: ["is_active", "active"])
                        )
                    )
                }
            }

            for (key, nested) in object where recursiveContainerKeys.contains(key) {
                candidates.append(contentsOf: collectWorkspaceCandidates(in: nested))
            }
            return candidates
        case .array(let items):
            return items.flatMap { collectWorkspaceCandidates(in: $0) }
        default:
            return []
        }
    }

    private static func extractString(from object: [String: JSONValue], keys: [String]) -> String? {
        for key in keys {
            if let value = AuthValueLookup.normalizedString(object[key]?.stringValue) {
                return value
            }
        }
        return nil
    }

    private static func extractBool(from object: [String: JSONValue], keys: [String]) -> Bool {
        keys.contains { key in object[key]?.boolValue == true }
    }

    private static func preferredWorkspaceIDs(
        from auth: JSONValue,
        claims: JSONValue?,
        accountIDHint: String?
    ) -> Set<String> {
        let hintPaths: [[String]] = [
            ["https://api.openai.com/auth", "chatgpt_org_id"],
            ["https://api.openai.com/auth", "chatgpt_organization_id"],
            ["https://api.openai.com/auth", "organization_id"],
            ["https://api.openai.com/auth", "org_id"],
            ["https://api.openai.com/auth", "active_organization_id"],
            ["https://api.openai.com/auth", "active_org_id"],
            ["https://api.openai.com/auth", "current_organization_id"],
            ["https://api.openai.com/auth", "default_organization_id"],
            ["tokens", "organization_id"],
            ["tokens", "org_id"],
            ["tokens", "active_organization_id"],
            ["tokens", "active_org_id"]
        ]

        var ids: Set<String> = []
        if let accountIDHint = AuthValueLookup.normalizedString(accountIDHint)?.lowercased() {
            ids.insert(accountIDHint)
        }

        for path in hintPaths {
            if let value = AuthValueLookup.normalizedString(AuthValueLookup.string(atPath: path, in: claims))?.lowercased() {
                ids.insert(value)
            }
            if let value = AuthValueLookup.normalizedString(AuthValueLookup.string(atPath: path, in: auth))?.lowercased() {
                ids.insert(value)
            }
        }
        return ids
    }
}

import Foundation

enum AccountWorkspaceStatus: String, Codable, Equatable {
    case active
    case deactivated
}

enum AccountDisplayStatus: String, Codable, Equatable {
    case list
    case pending
    case deactivated
    case deleted
}

enum WorkspaceDirectoryKind: String, Codable, Equatable {
    case workspace
    case personal
}

enum WorkspaceDirectoryStatus: String, Codable, Equatable {
    case unknown
    case active
    case deactivated
}

enum WorkspaceDirectoryVisibility: String, Codable, Equatable {
    case visible
    case deleted
}

enum WorkspaceDirectorySource: String, Codable, Equatable {
    case legacyMetadata
    case consent
    case deactivated
}

enum AccountProvider: String, Codable, Equatable, CaseIterable, Sendable {
    case codex
    case antigravity
    case cursor
}

enum AccountPlanLabel {
    static func normalized(from planType: String?, provider: AccountProvider = .codex) -> String {
        let normalized = planType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if provider == .antigravity {
            switch normalized {
            case "free":
                return "FREE"
            case "pro", "gemini-pro", "gemini_pro":
                return "GEMINI PRO"
            case "ultra", "ai_ultra", "gemini-ultra":
                return "ULTRA"
            default:
                return "GEMINI"
            }
        }

        switch normalized {
        case "free":
            return "FREE"
        case "plus":
            return "PLUS"
        case "pro", "pro_20x", "pro20x", "pro-20x", "chatgptpro":
            return "PRO 20X"
        case "prolite", "pro_lite", "pro-lite", "pro_5x", "pro5x", "pro-5x", "chatgptprolite":
            return "PRO 5X"
        case "enterprise":
            return "ENTERPRISE"
        case "business":
            return "BUSINESS"
        default:
            return "TEAM"
        }
    }

    static func normalized(
        usagePlanType: String?,
        storedPlanType: String?,
        provider: AccountProvider = .codex
    ) -> String {
        let usagePlanType = usagePlanType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let storedPlanType = storedPlanType?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let usageLabel = (usagePlanType?.isEmpty == false)
            ? normalized(from: usagePlanType, provider: provider)
            : nil
        let storedLabel = (storedPlanType?.isEmpty == false)
            ? normalized(from: storedPlanType, provider: provider)
            : nil

        if provider == .codex,
           let storedLabel,
           ["PRO 5X", "PRO 20X", "PLUS", "ENTERPRISE", "BUSINESS"].contains(storedLabel),
           usageLabel == nil || usageLabel == "TEAM" {
            return storedLabel
        }

        if let usageLabel {
            return usageLabel
        }
        if let storedLabel {
            return storedLabel
        }

        return normalized(from: nil as String?, provider: provider)
    }
}

enum WorkspaceDisplayName {
    static func normalized(from value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct WorkspaceDirectoryEntry: Codable, Equatable, Identifiable {
    var workspaceID: String
    var workspaceName: String?
    var email: String?
    var planType: String?
    var kind: WorkspaceDirectoryKind
    var source: WorkspaceDirectorySource = .legacyMetadata
    var status: WorkspaceDirectoryStatus = .unknown
    var visibility: WorkspaceDirectoryVisibility = .visible
    var lastSeenAt: Int64
    var lastStatusCheckedAt: Int64?

    enum CodingKeys: String, CodingKey {
        case workspaceID = "workspaceId"
        case workspaceName
        case email
        case planType
        case kind
        case source
        case status
        case visibility
        case lastSeenAt
        case lastStatusCheckedAt
    }

    var id: String {
        workspaceID
    }

    init(
        workspaceID: String,
        workspaceName: String?,
        email: String?,
        planType: String?,
        kind: WorkspaceDirectoryKind,
        source: WorkspaceDirectorySource = .legacyMetadata,
        status: WorkspaceDirectoryStatus = .unknown,
        visibility: WorkspaceDirectoryVisibility = .visible,
        lastSeenAt: Int64,
        lastStatusCheckedAt: Int64?
    ) {
        self.workspaceID = workspaceID
        self.workspaceName = workspaceName
        self.email = email
        self.planType = planType
        self.kind = kind
        self.source = source
        self.status = status
        self.visibility = visibility
        self.lastSeenAt = lastSeenAt
        self.lastStatusCheckedAt = lastStatusCheckedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspaceID = try container.decode(String.self, forKey: .workspaceID)
        workspaceName = try container.decodeIfPresent(String.self, forKey: .workspaceName)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        kind = try container.decode(WorkspaceDirectoryKind.self, forKey: .kind)
        source = try container.decodeIfPresent(WorkspaceDirectorySource.self, forKey: .source) ?? .legacyMetadata
        status = try container.decodeIfPresent(WorkspaceDirectoryStatus.self, forKey: .status) ?? .unknown
        visibility = try container.decodeIfPresent(WorkspaceDirectoryVisibility.self, forKey: .visibility) ?? .visible
        lastSeenAt = try container.decode(Int64.self, forKey: .lastSeenAt)
        lastStatusCheckedAt = try container.decodeIfPresent(Int64.self, forKey: .lastStatusCheckedAt)
    }
}

struct AccountsStore: Codable, Equatable {
    var version: Int = 1
    var accounts: [StoredAccount] = []
    var workspaceDirectory: [WorkspaceDirectoryEntry] = []
    var currentAccountID: String?
    var currentAntigravityAccountID: String?
    /// A credential was staged while AntiGravity was not running and the user
    /// disabled launch-after-switch. It is intentionally distinct from the
    /// verified native-current marker: the next local-RPC readback must still
    /// prove this account before it becomes current.
    var pendingAntigravityAccountID: String?
    var currentSelection: CurrentAccountSelection?

    enum CodingKeys: String, CodingKey {
        case version
        case accounts
        case workspaceDirectory
        case currentAccountID = "currentAccountId"
        case currentAntigravityAccountID = "currentAntigravityAccountId"
        case pendingAntigravityAccountID = "pendingAntigravityAccountId"
        case currentSelection
    }

    init(
        version: Int = 1,
        accounts: [StoredAccount] = [],
        workspaceDirectory: [WorkspaceDirectoryEntry] = [],
        currentAccountID: String? = nil,
        currentAntigravityAccountID: String? = nil,
        pendingAntigravityAccountID: String? = nil,
        currentSelection: CurrentAccountSelection? = nil
    ) {
        self.version = version
        self.accounts = accounts
        self.workspaceDirectory = workspaceDirectory
        self.currentAccountID = currentAccountID
        self.currentAntigravityAccountID = currentAntigravityAccountID
        self.pendingAntigravityAccountID = pendingAntigravityAccountID
        self.currentSelection = currentSelection
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        accounts = try container.decodeIfPresent([StoredAccount].self, forKey: .accounts) ?? []
        workspaceDirectory = try container.decodeIfPresent([WorkspaceDirectoryEntry].self, forKey: .workspaceDirectory) ?? []
        currentSelection = try container.decodeIfPresent(CurrentAccountSelection.self, forKey: .currentSelection)
        currentAccountID = try container.decodeIfPresent(String.self, forKey: .currentAccountID)
        currentAntigravityAccountID = try container.decodeIfPresent(String.self, forKey: .currentAntigravityAccountID)
        pendingAntigravityAccountID = try container.decodeIfPresent(String.self, forKey: .pendingAntigravityAccountID)
    }
}

struct CurrentAccountSelection: Codable, Equatable, Sendable {
    var cardID: String
    var selectedAt: Int64
    var sourceDeviceID: String

    enum CodingKeys: String, CodingKey {
        case cardID = "cardId"
        case legacyAccountID = "accountId"
        case selectedAt
        case sourceDeviceID
    }

    init(cardID: String, selectedAt: Int64, sourceDeviceID: String) {
        self.cardID = cardID
        self.selectedAt = selectedAt
        self.sourceDeviceID = sourceDeviceID
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cardID = try container.decodeIfPresent(String.self, forKey: .cardID)
            ?? container.decode(String.self, forKey: .legacyAccountID)
        selectedAt = try container.decode(Int64.self, forKey: .selectedAt)
        sourceDeviceID = try container.decode(String.self, forKey: .sourceDeviceID)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(cardID, forKey: .cardID)
        try container.encode(selectedAt, forKey: .selectedAt)
        try container.encode(sourceDeviceID, forKey: .sourceDeviceID)
    }
}

struct StoredAccount: Codable, Equatable, Identifiable {
    var id: String
    var label: String
    var email: String?
    var accountID: String
    var planType: String?
    var teamName: String?
    var teamAlias: String?
    var authJSON: JSONValue
    var addedAt: Int64
    var updatedAt: Int64
    var usage: UsageSnapshot?
    var usageError: String?
    var usageStateUpdatedAt: Int64 = 0
    var workspaceStatus: AccountWorkspaceStatus = .active
    var displayStatus: AccountDisplayStatus = .list
    var principalID: String? = nil
    var provider: AccountProvider = .codex

    enum CodingKeys: String, CodingKey {
        case id
        case label
        case email
        case accountID = "accountId"
        case planType
        case teamName
        case teamAlias
        case authJSON = "authJson"
        case addedAt
        case updatedAt
        case usage
        case usageError
        case usageStateUpdatedAt
        case workspaceStatus
        case displayStatus
        case principalID = "principalId"
        case provider
    }

    var accountKey: String {
        AccountIdentity.key(for: self)
    }

    init(
        id: String,
        label: String,
        email: String?,
        accountID: String,
        planType: String?,
        teamName: String?,
        teamAlias: String?,
        authJSON: JSONValue,
        addedAt: Int64,
        updatedAt: Int64,
        usage: UsageSnapshot?,
        usageError: String?,
        usageStateUpdatedAt: Int64? = nil,
        workspaceStatus: AccountWorkspaceStatus = .active,
        displayStatus: AccountDisplayStatus = .list,
        principalID: String? = nil,
        provider: AccountProvider = .codex
    ) {
        self.id = id
        self.label = label
        self.email = email
        self.accountID = accountID
        self.planType = planType
        self.teamName = teamName
        self.teamAlias = teamAlias
        self.authJSON = authJSON
        self.addedAt = addedAt
        self.updatedAt = updatedAt
        self.usage = usage
        self.usageError = usageError
        self.usageStateUpdatedAt = usageStateUpdatedAt
            ?? usage?.fetchedAt
            ?? (usageError == nil ? 0 : updatedAt)
        self.workspaceStatus = workspaceStatus
        self.displayStatus = displayStatus
        self.principalID = principalID
        self.provider = provider
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        accountID = try container.decode(String.self, forKey: .accountID)
        planType = try container.decodeIfPresent(String.self, forKey: .planType)
        teamName = try container.decodeIfPresent(String.self, forKey: .teamName)
        teamAlias = try container.decodeIfPresent(String.self, forKey: .teamAlias)
        authJSON = try container.decode(JSONValue.self, forKey: .authJSON)
        addedAt = try container.decode(Int64.self, forKey: .addedAt)
        updatedAt = try container.decode(Int64.self, forKey: .updatedAt)
        usage = try container.decodeIfPresent(UsageSnapshot.self, forKey: .usage)
        usageError = try container.decodeIfPresent(String.self, forKey: .usageError)
        usageStateUpdatedAt = try container.decodeIfPresent(Int64.self, forKey: .usageStateUpdatedAt)
            ?? usage?.fetchedAt
            ?? (usageError == nil ? 0 : updatedAt)
        workspaceStatus = try container.decodeIfPresent(AccountWorkspaceStatus.self, forKey: .workspaceStatus) ?? .active
        displayStatus = try container.decodeIfPresent(AccountDisplayStatus.self, forKey: .displayStatus)
            ?? (workspaceStatus == .deactivated ? .deactivated : .list)
        principalID = try container.decodeIfPresent(String.self, forKey: .principalID)
        provider = try container.decodeIfPresent(AccountProvider.self, forKey: .provider) ?? .codex
    }
}

struct AccountSummary: Equatable, Identifiable {
    var id: String
    var label: String
    var email: String?
    var accountID: String
    var planType: String?
    var teamName: String?
    var teamAlias: String?
    var addedAt: Int64
    var updatedAt: Int64
    var usage: UsageSnapshot?
    var usageError: String?
    var workspaceStatus: AccountWorkspaceStatus = .active
    var displayStatus: AccountDisplayStatus = .list
    var isCurrent: Bool
    /// This card's verified native credential is prepared for the next
    /// AntiGravity launch, but it is not asserted to be the running session.
    var isPendingNativeSwitch: Bool = false
    var principalID: String? = nil
    var provider: AccountProvider = .codex

    var accountKey: String {
        AccountIdentity.key(for: self)
    }

    var normalizedPlanLabel: String {
        AccountPlanLabel.normalized(
            usagePlanType: usage?.planType,
            storedPlanType: planType,
            provider: provider
        )
    }

    var displayTeamName: String? {
        if let alias = teamAlias?.trimmingCharacters(in: .whitespacesAndNewlines),
           !alias.isEmpty {
            return alias
        }
        if let teamName = teamName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !teamName.isEmpty {
            return teamName
        }
        return nil
    }

    var shouldDisplayWorkspaceTag: Bool {
        switch normalizedPlanLabel {
        case "TEAM", "BUSINESS", "ENTERPRISE":
            return displayTeamName != nil
        default:
            return false
        }
    }

    var isWorkspaceDeactivated: Bool {
        if displayStatus == .deleted {
            return false
        }
        return displayStatus == .deactivated || workspaceStatus == .deactivated
    }

    var isPendingDisplay: Bool {
        displayStatus == .pending
    }

    var isHidden: Bool {
        displayStatus == .deleted
    }

    var isVisibleInMainList: Bool {
        displayStatus == .list
    }
}

extension AccountsStore {
    func accountSummaries() -> [AccountSummary] {
        return accounts.map { account in
            AccountSummary(
                id: account.id,
                label: account.label,
                email: account.email,
                accountID: account.accountID,
                planType: account.planType,
                teamName: account.teamName,
                teamAlias: account.teamAlias,
                addedAt: account.addedAt,
                updatedAt: account.updatedAt,
                usage: account.usage,
                usageError: account.usageError,
                workspaceStatus: account.workspaceStatus,
                displayStatus: account.displayStatus,
                isCurrent: account.provider == .antigravity
                    ? currentAntigravityAccountID == account.id
                    : currentAccountID == account.id,
                isPendingNativeSwitch: account.provider == .antigravity
                    && pendingAntigravityAccountID == account.id,
                principalID: account.principalID,
                provider: account.provider
            )
        }
    }
}

/// Identifies the origin of a usage snapshot.  In particular, model discovery is
/// deliberately distinct from a quota summary: an all-available model list is not
/// evidence that an account has 100% quota remaining.
enum UsageSnapshotSource: String, Codable, Equatable, Sendable {
    case codexRemote
    case antigravityNativeSummary
    case antigravityAgySummary
    case antigravityRemoteQuota
    case antigravityRemoteAvailability
    case unknown

    var isAuthoritativeQuota: Bool {
        switch self {
        case .antigravityNativeSummary, .antigravityAgySummary, .antigravityRemoteQuota:
            return true
        case .codexRemote, .antigravityRemoteAvailability, .unknown:
            return false
        }
    }
}

/// A named quota group from AntiGravity's `RetrieveUserQuotaSummary` response.
/// Keeping the server names avoids incorrectly presenting independent Gemini and
/// Claude/GPT pools as fixed "Pro" and "Flash" bars.
struct UsageQuotaFamily: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var buckets: [UsageQuotaBucket]
}

enum QuotaCountdownStartEvidence: String, Codable, Equatable, Sendable {
    case requestObserved
}

struct UsageQuotaBucket: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var displayName: String
    var usedPercent: Double?
    var resetAt: Int64?
    var windowSeconds: Int64?
    var resetDescription: String?
    var isUsageKnown: Bool
    /// Local lower bound for the first request observed in this reset window.
    /// It is intentionally separate from the provider's absolute reset time.
    var countdownStartedAt: Int64? = nil
    /// Missing in older stores; those markers are intentionally invalidated.
    var countdownStartEvidence: QuotaCountdownStartEvidence? = nil

    /// A stable, provider-neutral ordering key. It intentionally relies on
    /// canonical window metadata and bucket IDs, never a localized display
    /// label that may have been serialized by an older app version.
    var cadenceRank: Int {
        switch windowSeconds {
        case 5 * 60 * 60:
            return 0
        case 7 * 24 * 60 * 60:
            return 1
        default:
            break
        }
        let identifier = id.lowercased()
        if identifier.contains("5h") || identifier.contains("five_hour") || identifier.contains("pt5h") || identifier.contains("session") {
            return 0
        }
        if identifier.contains("week") || identifier.contains("p7d") {
            return 1
        }
        return 2
    }
}

extension UsageSnapshot {
    var quotaBuckets: [UsageQuotaBucket] {
        quotaFamilies?.flatMap(\.buckets) ?? []
    }

    /// Codex can report named `additional_rate_limits` alongside its standard
    /// account limit.  They are deliberately not folded into AntiGravity's
    /// `quotaFamilies`: the providers have different authority and switching
    /// semantics, and a named Codex pool must remain independently selectable
    /// in the presentation preferences.
    var codexAdditionalQuotaBuckets: [UsageQuotaBucket] {
        codexQuotaFamilies?.flatMap(\.buckets) ?? []
    }

    var knownQuotaBuckets: [UsageQuotaBucket] {
        quotaBuckets.filter { $0.isUsageKnown && $0.usedPercent != nil }
    }

    var hasAuthoritativeQuota: Bool {
        guard let source, source.isAuthoritativeQuota else { return false }
        return !knownQuotaBuckets.isEmpty
    }

    var isVerifiedForSwitch: Bool {
        // Background session changes need a complete, identity-matched native
        // summary. One known bucket beside an unknown/disabled peer remains
        // useful for display, but is not enough evidence to choose an account.
        hasAuthoritativeQuota
            && sourceAccountMatched == true
            && !quotaBuckets.isEmpty
            && quotaBuckets.allSatisfy { bucket in
                bucket.isUsageKnown && bucket.usedPercent?.isFinite == true
            }
    }

    func isStale(now: Int64, maximumAge: Int64 = 15 * 60) -> Bool {
        fetchedAt <= 0 || now - fetchedAt > maximumAge
    }

    /// Legacy two-window consumers (widgets/tray) get representatives from the
    /// actual summary, never invented provider bars.  Full cards use
    /// `quotaFamilies` directly.
    var compactQuotaWindows: [UsageQuotaBucket] {
        let known = knownQuotaBuckets
        guard !known.isEmpty else { return [] }
        return known.sorted { left, right in
            if left.cadenceRank != right.cadenceRank {
                return left.cadenceRank < right.cadenceRank
            }
            let leftUsed = left.usedPercent ?? -1
            let rightUsed = right.usedPercent ?? -1
            if leftUsed != rightUsed {
                return leftUsed > rightUsed
            }
            return left.id.localizedCaseInsensitiveCompare(right.id) == .orderedAscending
        }
    }
}

struct UsageSnapshot: Codable, Equatable {
    var fetchedAt: Int64
    var planType: String?
    var fiveHour: UsageWindow?
    var oneWeek: UsageWindow?
    var credits: CreditSnapshot?
    /// Optional fields preserve compatibility with account stores created before
    /// AntiGravity gained named quota families.
    var quotaFamilies: [UsageQuotaFamily]? = nil
    /// Named non-standard Codex windows reported by `additional_rate_limits`.
    /// This is optional for backward compatibility with previously persisted
    /// snapshots and is never consulted by account-ranking code.
    var codexQuotaFamilies: [UsageQuotaFamily]? = nil
    var source: UsageSnapshotSource? = nil
    var sourceAccountMatched: Bool? = nil
    var resetCredits: ResetCreditInventory? = nil
}

struct ResetCreditInventory: Codable, Equatable {
    var availableCount: Int
    var expiresAt: [Date]
    var fetchedAt: Date
}

struct UsageWindow: Codable, Equatable {
    var usedPercent: Double
    var windowSeconds: Int64
    var resetAt: Int64?
    /// Local lower bound for the first request observed in this reset window.
    var countdownStartedAt: Int64? = nil
    /// Missing in older stores; those markers are intentionally invalidated.
    var countdownStartEvidence: QuotaCountdownStartEvidence? = nil
}

struct CreditSnapshot: Codable, Equatable {
    var hasCredits: Bool
    var unlimited: Bool
    var balance: String?
}

struct ExtractedAuth: Equatable {
    var accountID: String
    var accessToken: String
    var email: String?
    var planType: String?
    var teamName: String?
    var principalID: String? = nil
    var provider: AccountProvider = .codex

    var accountKey: String {
        AccountIdentity.key(for: self)
    }
}

struct WorkspaceMetadata: Equatable, Sendable {
    var accountID: String
    var workspaceName: String?
    var structure: String?
}

enum WorkspaceAuthorizationCandidateStatus: Equatable, Sendable {
    case pending
    case deactivated
}

struct WorkspaceAuthorizationCandidate: Equatable, Identifiable, Sendable {
    var workspaceID: String
    var workspaceName: String
    var email: String?
    var planType: String?
    var status: WorkspaceAuthorizationCandidateStatus = .pending

    var id: String {
        workspaceID
    }
}

struct ConsentWorkspaceOption: Equatable, Sendable {
    var workspaceID: String
    var workspaceName: String
    var kind: WorkspaceDirectoryKind
}

struct ChatGPTOAuthTokens: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var idToken: String
    var apiKey: String?
    var consentWorkspaces: [ConsentWorkspaceOption] = []
}

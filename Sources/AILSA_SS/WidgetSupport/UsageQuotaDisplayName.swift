import Foundation

/// Presentation-only names for provider quota data. `UsageQuotaBucket` and
/// `UsageQuotaFamily` persist canonical server values so stores remain locale
/// neutral and can be shared by the app, tray and widget.
enum UsageQuotaDisplayName {
    static func bucket(_ bucket: UsageQuotaBucket) -> String {
        switch bucket.windowSeconds {
        case 5 * 60 * 60:
            return L10n.tr("accounts.window.five_hour")
        case 7 * 24 * 60 * 60:
            return L10n.tr("accounts.window.one_week")
        default:
            break
        }

        let identifier = bucket.id.lowercased()
        if identifier.contains("5h") || identifier.contains("five_hour") || identifier.contains("pt5h") {
            return L10n.tr("accounts.window.five_hour")
        }
        if identifier.contains("week") || identifier.contains("p7d") {
            return L10n.tr("accounts.window.one_week")
        }

        // r3 briefly serialized localization keys. Treat them as legacy input
        // at the presentation boundary; fresh snapshots keep their original
        // server labels above.
        switch bucket.displayName {
        case "accounts.window.five_hour":
            return L10n.tr("accounts.window.five_hour")
        case "accounts.window.one_week":
            return L10n.tr("accounts.window.one_week")
        default:
            return bucket.displayName
        }
    }

    static func family(_ family: UsageQuotaFamily) -> String {
        switch family.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "gemini models":
            return L10n.tr("accounts.quota.family.gemini")
        // Providers have shipped the same Claude/GPT bucket under several
        // labels; they are one family and should get one translated name.
        case "claude and gpt models", "third-party", "third party", "third_party":
            return L10n.tr("accounts.quota.family.claude_gpt")
        case "remote verified models":
            return L10n.tr("accounts.window.remote_verified_models")
        default:
            return family.displayName
        }
    }
}

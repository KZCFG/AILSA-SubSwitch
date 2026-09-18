import Foundation

enum AccountDisplayNameStyle: Sendable {
    case full
    case localPart
}

enum AccountDisplayNameFormatter {
    static func format(account: AccountSummary, style: AccountDisplayNameStyle) -> String {
        let raw = (account.email ?? account.accountID).trimmingCharacters(in: .whitespacesAndNewlines)

        switch style {
        case .full:
            return raw
        case .localPart:
            guard let atIndex = raw.firstIndex(of: "@"),
                  atIndex > raw.startIndex else {
                return raw
            }
            return String(raw[..<atIndex])
        }
    }
}

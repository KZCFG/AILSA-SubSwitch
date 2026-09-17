import Foundation

enum AppVersion {
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var buildDate: String {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "ASSBuildDate") as? String,
              let date = ISO8601DateFormatter().date(from: raw) else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static var current: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String

        if let short, !short.isEmpty {
            if let label = info?["ASSBuildLabel"] as? String, !label.isEmpty, label != short { return "\(short) (\(label))" }
            return short
        }
        if let build, !build.isEmpty {
            return build
        }
        return "0.0.0"
    }
}

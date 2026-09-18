import Foundation

enum ChatGPTBaseOriginResolver {
    static func resolve(configPath: URL) -> String {
        guard let raw = try? String(contentsOf: configPath, encoding: .utf8), !raw.isEmpty else {
            return "https://chatgpt.com"
        }

        for line in raw.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("chatgpt_base_url") else { continue }
            guard let equalIndex = trimmed.firstIndex(of: "=") else { continue }
            let value = trimmed[trimmed.index(after: equalIndex)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty {
                return value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            }
        }

        return "https://chatgpt.com"
    }
}


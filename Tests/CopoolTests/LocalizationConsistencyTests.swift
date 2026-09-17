import Foundation
import XCTest

final class LocalizationConsistencyTests: XCTestCase {
    private let locales = ["en", "zh-Hans", "ja", "ko"]

    func testLocaleKeySetsMatchEnglish() throws {
        let english = try localizationMap(for: "en")
        XCTAssertFalse(english.isEmpty)

        for locale in locales where locale != "en" {
            let map = try localizationMap(for: locale)
            XCTAssertEqual(
                Set(map.keys),
                Set(english.keys),
                "Localization keys do not match English for \(locale)"
            )
        }
    }

    func testSourceLocalizationKeysExistInAllLocales() throws {
        let sourceKeys = try collectLocalizationKeysUsedInSource()
        XCTAssertFalse(sourceKeys.isEmpty)

        for locale in locales {
            let map = try localizationMap(for: locale)
            let missing = sourceKeys.subtracting(map.keys)
            XCTAssertTrue(missing.isEmpty, "Missing keys in \(locale): \(missing.sorted())")
        }
    }

    func testErrorStringsAreTranslatedInNonEnglishLocales() throws {
        let english = try localizationMap(for: "en")

        for locale in locales where locale != "en" {
            let map = try localizationMap(for: locale)
            let untranslated = map.keys
                .filter { $0.hasPrefix("error.") }
                .filter { map[$0] == english[$0] }
            XCTAssertTrue(untranslated.isEmpty, "Untranslated error keys in \(locale): \(untranslated.sorted())")
        }
    }

    private func localizationMap(for locale: String) throws -> [String: String] {
        let path = resourcesRoot()
            .appendingPathComponent("\(locale).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings", isDirectory: false)
        let content = try String(contentsOf: path, encoding: .utf8)
        return parseStringsFile(content)
    }

    private func resourcesRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CopoolTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // project root
            .appendingPathComponent("Sources/Copool/Resources", isDirectory: true)
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Copool", isDirectory: true)
    }

    private func collectLocalizationKeysUsedInSource() throws -> Set<String> {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot(),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let l10nPattern = try NSRegularExpression(pattern: #"L10n\.tr\("([^"]+)""#)
        let keyedControlPattern = try NSRegularExpression(
            pattern: #"(Text|Button|Toggle|Section|Picker|Label)\("([a-z0-9_]+\.[a-z0-9_\.]+)""#,
            options: [.caseInsensitive]
        )

        var keys = Set<String>()
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
            let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)

            for match in l10nPattern.matches(in: content, options: [], range: nsRange) {
                guard
                    let range = Range(match.range(at: 1), in: content)
                else { continue }
                keys.insert(String(content[range]))
            }

            for match in keyedControlPattern.matches(in: content, options: [], range: nsRange) {
                guard
                    let range = Range(match.range(at: 2), in: content)
                else { continue }
                keys.insert(String(content[range]))
            }
        }
        return keys
    }

    private func parseStringsFile(_ content: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in content.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("\""), line.contains("="), line.hasSuffix(";") else { continue }
            guard
                let keyEnd = line.dropFirst().firstIndex(of: "\"")
            else { continue }

            let key = String(line[line.index(after: line.startIndex)..<keyEnd])
            guard
                let equals = line.firstIndex(of: "="),
                let valueStartQuote = line[line.index(after: equals)...].firstIndex(of: "\"")
            else { continue }
            let afterValueStart = line.index(after: valueStartQuote)
            guard let valueEndQuote = line[afterValueStart...].lastIndex(of: "\"") else { continue }
            let value = String(line[afterValueStart..<valueEndQuote])
            result[key] = value
        }
        return result
    }
}

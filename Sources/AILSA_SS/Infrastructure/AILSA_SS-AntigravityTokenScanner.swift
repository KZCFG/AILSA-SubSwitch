// Bounded local metadata codecs adapted from CodexBar v0.81.0, commit ee890b5f392e70d6e20162d3e95cf9f1be265b60.
// See THIRD_PARTY_NOTICES.md for provenance and the complete MIT notice.
/*
MIT License

Copyright (c) 2026 Peter Steinberger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
import Foundation
extension AntigravityTokenScanner {
    struct Limits: Sendable {
        var databases = 500
        var directoryEntries = 10000
        var rowsPerDatabase = 10000
        var rows = 100_000
        // Native IDE tool envelopes can exceed the CLI-oriented 16 MiB cap.
        // Keep a 64 MiB per-blob/database ceiling and 512 MiB job ceiling.
        var blobBytes = 64 * 1024 * 1024
        var databaseBytes = 64 * 1024 * 1024
        var bytes = 512 * 1024 * 1024
        var schemaEntries = 128
        var schemaColumns = 64
        var schemaBytes = 64 * 1024
        var duration: TimeInterval = 30
    }

    struct Statistics: Sendable {
        var directoryEntries = 0
        var files = 0
        var rows = 0
        var attemptedBytes = 0
        var materializedPayloadBytes = 0
        var schemaEntries = 0
        var schemaColumns = 0
        var schemaBytes = 0
        var sqliteHandlesOpened = 0
        var sqliteHandlesClosed = 0
        /// Sidecar-less WAL databases that the ordinary read-only open declined and an immutable open read.
        var immutableFallbacks = 0
        /// Databases in a declared root whose schema has no gen_metadata table; skipped without affecting coverage.
        var foreignDatabases = 0
    }

    enum ScanFailure: Error {
        case exhausted
        /// Schema-budget exhaustion (bytes, entries, or columns). Unlike hard row/byte/duration exhaustion,
        /// schema exhaustion preserves already-decoded rows as partial history instead of withholding the report.
        case schemaExhausted
        case invalid
    }

    /// One budget belongs to one executor job, including discovery and fallback.
    final class Budget {
        let limits: Limits
        let cancellation: () throws -> Void
        let clock: () -> TimeInterval
        let started: TimeInterval
        var statistics = Statistics()
        /// Schema text inspected in the current database. The schema allowance applies to each database,
        /// like the entry and column limits, so a long history of small schemas never adds up to it.
        private(set) var databaseSchemaBytes = 0

        init(
            limits: Limits,
            clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
            cancellation: @escaping () throws -> Void)
        {
            self.limits = limits
            self.clock = clock
            self.started = clock()
            self.cancellation = cancellation
        }

        func check() throws {
            try self.cancellation()
            guard self.clock() - self.started < self.limits.duration else { throw ScanFailure.exhausted }
        }

        func chargeBytes(_ count: Int) throws {
            try self.check()
            let (attempted, overflow) = self.statistics.attemptedBytes.addingReportingOverflow(count)
            self.statistics.attemptedBytes = overflow ? Int.max : attempted
            guard !overflow, attempted <= self.limits.bytes else { throw ScanFailure.exhausted }
        }

        func chargeRow() throws {
            try self.check()
            self.statistics.rows += 1
            guard self.statistics.rows <= self.limits.rows else { throw ScanFailure.exhausted }
        }

        func beginDatabase() {
            self.databaseSchemaBytes = 0
        }

        func chargeSchemaBytes(_ count: Int) throws {
            try self.check()
            let (total, totalOverflow) = self.statistics.schemaBytes.addingReportingOverflow(count)
            self.statistics.schemaBytes = totalOverflow ? Int.max : total
            let (attempted, overflow) = self.databaseSchemaBytes.addingReportingOverflow(count)
            self.databaseSchemaBytes = overflow ? Int.max : attempted
            guard !overflow, attempted <= self.limits.schemaBytes else { throw ScanFailure.schemaExhausted }
        }
    }

    struct Discovery {
        var paths: [URL] = []
        var isComplete = true
    }

    static func discover(roots: [URL], extension suffix: String, budget: Budget) throws -> Discovery {
        var result = Discovery()
        for root in roots {
            try budget.check()
            do {
                let values = try root.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey])
                guard values.isDirectory == true else {
                    result.isComplete = false
                    continue
                }
            } catch {
                // ENOENT means absent. Permission errors and invalid roots must block fallback.
                if (error as NSError).code == NSFileReadNoSuchFileError { continue }
                result.isComplete = false
                continue
            }
            var enumerationFailed = false
            guard let enumerator = FileManager.default.enumerator(
                at: root.resolvingSymlinksInPath(),
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsSubdirectoryDescendants],
                errorHandler: { _, _ in
                    enumerationFailed = true
                    return false
                })
            else {
                result.isComplete = false
                continue
            }
            while true {
                try budget.check()
                guard let url = enumerator.nextObject() as? URL else { break }
                budget.statistics.directoryEntries += 1
                guard budget.statistics.directoryEntries <= budget.limits.directoryEntries else {
                    throw ScanFailure.exhausted
                }
                guard !url.lastPathComponent.hasPrefix("."), url.pathExtension.lowercased() == suffix else { continue }
                guard result.paths.count < budget.limits.databases else {
                    throw ScanFailure.exhausted
                }
                do {
                    let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else {
                        result.isComplete = false
                        continue
                    }
                    result.paths.append(url)
                } catch {
                    result.isComplete = false
                }
            }
            if enumerationFailed { result.isComplete = false }
        }
        result.paths.sort { $0.path < $1.path }
        return result
    }
}


// Upstream AntigravityTokenProto.swift
import Foundation

/// Decodes only the independently recorded generation layout; no inferred opaque timestamps.
struct AntigravityTokenProto {
    private let bytes: ArraySlice<UInt8>
    private var offset: Int
    private(set) var isMalformed = false

    init(bytes: [UInt8]) {
        self.init(slice: bytes[...])
    }

    private init(slice: ArraySlice<UInt8>) {
        self.bytes = slice
        self.offset = slice.startIndex
    }

    struct ParsedUsage: Equatable, Sendable {
        var newInput = 0
        var cacheRead = 0
        var output = 0
        var reasoning = 0
        var responseID: String?
        /// Field 1: the model enum ID (e.g. 1298 for `gemini-3.7-flash`). Validated and kept for
        /// copied-row identity; never counted as tokens. Absent for JSONL-sourced usage.
        var modelID: Int?
        fileprivate var botIdentifier = AuxiliaryIdentifier()

        var botID: String? {
            self.botIdentifier.value
        }
    }

    struct ParsedTurn: Equatable, Sendable {
        var usage: ParsedUsage?
        var timestampMs: Int64?
        var model: String?
        var label: String?
        var stepUUID: String?
    }

    private struct Timestamp {
        var seconds: UInt64?
        var nanos: UInt64 = 0

        func milliseconds() throws -> Int64? {
            guard let seconds else { return nil }
            guard seconds > 0, seconds <= 253_402_300_799, self.nanos <= 999_999_999,
                  let seconds = Int64(exactly: seconds), let nanos = Int64(exactly: self.nanos)
            else { throw AntigravityTokenScanner.ScanFailure.invalid }
            return seconds * 1000 + nanos / 1_000_000
        }
    }

    struct Field {
        let number: Int
        let wire: Int
        let data: ArraySlice<UInt8>?
        let value: UInt64?

        func message() throws -> ArraySlice<UInt8> {
            guard self.wire == 2, let data else { throw AntigravityTokenScanner.ScanFailure.invalid }
            return data
        }

        func integer() throws -> UInt64 {
            guard self.wire == 0, let value else { throw AntigravityTokenScanner.ScanFailure.invalid }
            return value
        }

        func counter() throws -> Int {
            guard let value = try Int(exactly: self.integer()) else {
                throw AntigravityTokenScanner.ScanFailure.invalid
            }
            return value
        }

        func string() throws -> String? {
            guard let data, data.count <= 4096, let text = try String(bytes: self.message(), encoding: .utf8) else {
                throw AntigravityTokenScanner.ScanFailure.invalid
            }
            // Preserve raw identities for conflict detection; whitespace-only optional fields are absent.
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
        }
    }

    fileprivate struct AuxiliaryIdentifier: Equatable, Sendable {
        private(set) var value: String?
        private var isValid = true

        static func == (lhs: Self, rhs: Self) -> Bool {
            // Parser invalidity is not part of finalized event identity or copied-row deduplication.
            lhs.value == rhs.value
        }

        mutating func read(_ field: Field) throws {
            do {
                let value = try field.string()
                if self.isValid {
                    self.value = value
                }
            } catch AntigravityTokenScanner.ScanFailure.invalid {
                self.invalidate()
            }
        }

        mutating func invalidate() {
            self.value = nil
            self.isValid = false
        }
    }

    mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        for index in 0..<10 {
            guard self.offset < self.bytes.endIndex else { break }
            let byte = self.bytes[self.offset]
            self.offset += 1
            if index == 9, byte > 1 {
                break
            }
            result |= UInt64(byte & 0x7F) << (index * 7)
            if byte & 0x80 == 0 {
                return result
            }
        }
        self.isMalformed = true
        return nil
    }

    mutating func nextField() -> Field? {
        guard self.offset < self.bytes.endIndex else { return nil }
        guard let tag = self.readVarint(), tag >> 3 > 0, tag >> 3 <= 536_870_911 else {
            self.isMalformed = true
            return nil
        }
        let number = Int(tag >> 3)
        let wire = Int(tag & 7)
        if wire == 0 {
            guard let value = self.readVarint() else { return nil }
            return Field(number: number, wire: wire, data: nil, value: value)
        }
        let count: Int? = switch wire {
        case 1: 8
        case 2: self.readVarint().flatMap(Int.init(exactly:))
        case 5: 4
        default: nil
        }
        guard let count, count <= self.bytes.endIndex - self.offset else {
            self.isMalformed = true
            return nil
        }
        let end = self.offset + count
        let data = self.bytes[self.offset..<end]
        self.offset = end
        return Field(number: number, wire: wire, data: data, value: nil)
    }

    private static func fields(
        _ bytes: ArraySlice<UInt8>,
        checkCancellation: () throws -> Void,
        visit: (Field) throws -> Void) throws
    {
        var reader = Self(slice: bytes)
        while reader.offset < reader.bytes.endIndex {
            try checkCancellation()
            guard let field = reader.nextField() else { break }
            try visit(field)
        }
        guard !reader.isMalformed else { throw AntigravityTokenScanner.ScanFailure.invalid }
    }

    static func parseTurn(
        _ rootBytes: [UInt8],
        checkCancellation: () throws -> Void = {}) throws -> ParsedTurn?
    {
        var turn = ParsedTurn()
        var time = Timestamp()
        var foundChat = false
        do {
            // Repeated singular messages merge, scalars use last-one-wins. Every occurrence is validated.
            try self.fields(rootBytes[...], checkCancellation: checkCancellation) { field in
                switch field.number {
                case 1:
                    foundChat = true
                    try self.parseChat(
                        field.message(), turn: &turn, time: &time, checkCancellation: checkCancellation)
                case 4:
                    turn.stepUUID = try field.string()
                default:
                    break
                }
            }
            guard foundChat else { return nil }
            turn.timestampMs = try time.milliseconds()
            return turn
        } catch AntigravityTokenScanner.ScanFailure.invalid {
            return nil
        }
    }

    struct StepMetadata: Equatable, Sendable {
        var stepUUID: String?
        var botID: String?
        var timestampMs: Int64?
    }

    static func parseStepMetadata(
        _ bytes: [UInt8],
        checkCancellation: () throws -> Void = {}) throws -> StepMetadata?
    {
        var stepUUID: String?
        var botIdentifier = AuxiliaryIdentifier()
        var time = Timestamp()
        var timestampIsValid = true
        do {
            try self.fields(bytes[...], checkCancellation: checkCancellation) { field in
                switch field.number {
                case 1:
                    do {
                        try self.parseTimestampField(
                            field.message(), time: &time, checkCancellation: checkCancellation)
                    } catch AntigravityTokenScanner.ScanFailure.invalid {
                        timestampIsValid = false
                    }
                case 9:
                    // Malformed auxiliary IDs disable exact matching, even if a later envelope is valid.
                    do {
                        try self.fields(field.message(), checkCancellation: checkCancellation) { subfield in
                            if subfield.number == 7 {
                                try botIdentifier.read(subfield)
                            }
                        }
                    } catch AntigravityTokenScanner.ScanFailure.invalid {
                        botIdentifier.invalidate()
                    }
                case 12:
                    stepUUID = try field.string()
                default:
                    break
                }
            }
            let ms = timestampIsValid ? try time.milliseconds() : nil
            return StepMetadata(stepUUID: stepUUID, botID: botIdentifier.value, timestampMs: ms)
        } catch AntigravityTokenScanner.ScanFailure.invalid {
            return nil
        }
    }

    private static func parseChat(
        _ bytes: ArraySlice<UInt8>,
        turn: inout ParsedTurn,
        time: inout Timestamp,
        checkCancellation: () throws -> Void) throws
    {
        try self.fields(bytes, checkCancellation: checkCancellation) { field in
            switch field.number {
            case 4:
                var usage = turn.usage ?? ParsedUsage()
                try self.parseUsage(field.message(), usage: &usage, checkCancellation: checkCancellation)
                turn.usage = usage
            case 9:
                try self.parseGeneration(field.message(), time: &time, checkCancellation: checkCancellation)
            case 19: turn.model = try field.string()
            case 21: turn.label = try field.string()
            default: break
            }
        }
    }

    private static func parseUsage(
        _ bytes: ArraySlice<UInt8>,
        usage: inout ParsedUsage,
        checkCancellation: () throws -> Void) throws
    {
        try self.fields(bytes, checkCancellation: checkCancellation) { field in
            switch field.number {
            case 1:
                // Field 1 is the model enum ID (e.g. 1298 for gemini-3.7-flash), not a token count.
                // Keep it for copied-row identity so two rows differing only here still conflict,
                // but never add it to input or total tokens.
                usage.modelID = try field.counter()
            case 2: usage.newInput = try field.counter()
            case 5: usage.cacheRead = try field.counter()
            case 7: try usage.botIdentifier.read(field)
            case 9: usage.reasoning = try field.counter()
            case 10: usage.output = try field.counter()
            case 11: usage.responseID = try field.string()
            default: break
            }
        }
    }

    private static func parseTimestampField(
        _ bytes: ArraySlice<UInt8>,
        time: inout Timestamp,
        checkCancellation: () throws -> Void) throws
    {
        try self.fields(bytes, checkCancellation: checkCancellation) { stamp in
            switch stamp.number {
            case 1:
                let seconds = try stamp.integer()
                guard seconds > 0, seconds <= 253_402_300_799 else {
                    throw AntigravityTokenScanner.ScanFailure.invalid
                }
                time.seconds = seconds
            case 2:
                let nanos = try stamp.integer()
                guard nanos <= 999_999_999 else { throw AntigravityTokenScanner.ScanFailure.invalid }
                time.nanos = nanos
            default: break
            }
        }
    }

    private static func parseGeneration(
        _ bytes: ArraySlice<UInt8>,
        time: inout Timestamp,
        checkCancellation: () throws -> Void) throws
    {
        try self.fields(bytes, checkCancellation: checkCancellation) { field in
            guard field.number == 4 else { return }
            try self.parseTimestampField(field.message(), time: &time, checkCancellation: checkCancellation)
        }
    }
}

// Upstream AntigravityTokenJSON.swift
import Foundation

/// Preserve number lexemes before Foundation can round them. Foundation still validates JSON structure and strings.
enum AntigravityTokenJSON {
    struct Number {
        let integer: Int?
    }

    private enum Invalid: Error { case syntax }

    static func decode(_ bytes: [UInt8], checkCancellation: @escaping () throws -> Void) throws -> [String: Any]? {
        do {
            var lexer = Lexer(bytes: bytes, masked: bytes, checkCancellation: checkCancellation)
            return try lexer.object()
        } catch Invalid.syntax {
            return nil
        }
    }

    private static func foundationValue(_ bytes: ArraySlice<UInt8>) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: Data(bytes), options: [.fragmentsAllowed])
        } catch {
            throw Invalid.syntax
        }
    }

    private struct Lexer {
        let bytes: [UInt8]
        var masked: [UInt8]
        let checkCancellation: () throws -> Void
        var index = 0

        mutating func object() throws -> [String: Any] {
            var depth = 0
            var key: String?
            var expectingKey = true
            var keys = Set<String>()
            var numbers: [String: Number] = [:]
            while let byte = self.current {
                switch byte {
                case 34:
                    let start = self.index
                    try self.string()
                    if depth == 1, expectingKey {
                        guard let name = try AntigravityTokenJSON.foundationValue(self.bytes[start..<self.index])
                            as? String,
                            keys.insert(name).inserted else { throw Invalid.syntax }
                        key = name
                        expectingKey = false
                    }
                case 123, 91:
                    depth += 1
                    guard depth <= 512 else { throw Invalid.syntax }
                    try self.advance()
                case 125, 93:
                    depth -= 1
                    guard depth >= 0 else { throw Invalid.syntax }
                    try self.advance()
                case 44:
                    if depth == 1 {
                        key = nil
                        expectingKey = true
                    }
                    try self.advance()
                case 45, 48...57:
                    let start = self.index
                    let value = try self.number()
                    if depth == 1, let key { numbers[key] = Number(integer: value) }
                    // Keep byte positions/JSON separators, replacing only a fully validated numeric token.
                    self.masked[start] = 48
                    for offset in (start + 1)..<self.index {
                        if offset % 4096 == 0 { try self.checkCancellation() }
                        self.masked[offset] = 32
                    }
                default: try self.advance()
                }
            }
            try self.checkCancellation()
            guard var object = try AntigravityTokenJSON.foundationValue(self.masked[...]) as? [String: Any] else {
                throw Invalid.syntax
            }
            for (index, entry) in numbers.enumerated() {
                if index % 256 == 0 { try self.checkCancellation() }
                object[entry.key] = entry.value
            }
            return object
        }

        private var current: UInt8? {
            self.index < self.bytes.count ? self.bytes[self.index] : nil
        }

        private var isDigit: Bool {
            self.current.map { (48...57).contains($0) } ?? false
        }

        private mutating func advance() throws {
            if self.index % 4096 == 0 { try self.checkCancellation() }
            self.index += 1
        }

        private mutating func string() throws {
            try self.advance()
            while let byte = self.current {
                try self.advance()
                if byte == 34 { return }
                if byte == 92 {
                    guard self.current != nil else { throw Invalid.syntax }
                    try self.advance()
                }
            }
            throw Invalid.syntax
        }

        private mutating func number() throws -> Int? {
            let negative = self.current == 45
            if negative { try self.advance() }
            guard self.isDigit else { throw Invalid.syntax }
            var digits: [UInt8] = []
            var significantCount = 0
            var trailingZeros = 0
            func record(_ byte: UInt8) {
                guard byte != 48 || significantCount > 0 else { return }
                significantCount += 1
                trailingZeros = byte == 48 ? trailingZeros + 1 : 0
                if digits.count < 19 { digits.append(byte - 48) }
            }
            if self.current == 48 {
                try self.advance()
                guard !self.isDigit else { throw Invalid.syntax }
            } else {
                while self.isDigit {
                    record(self.bytes[self.index])
                    try self.advance()
                }
            }
            var fractionDigits = 0
            if self.current == 46 {
                try self.advance()
                guard self.isDigit else { throw Invalid.syntax }
                while self.isDigit {
                    record(self.bytes[self.index])
                    fractionDigits += 1
                    try self.advance()
                }
            }
            var exponent = 0
            if self.current == 69 || self.current == 101 {
                try self.advance()
                let negativeExponent = self.current == 45
                if self.current == 43 || negativeExponent { try self.advance() }
                guard self.isDigit else { throw Invalid.syntax }
                while self.isDigit {
                    // A larger exponent cannot be cancelled by this bounded token's fractional digits.
                    exponent = min(exponent * 10 + Int(self.bytes[self.index] - 48), self.bytes.count + 20)
                    try self.advance()
                }
                if negativeExponent { exponent = -exponent }
            }
            if significantCount == 0 { return 0 }
            let count = significantCount - trailingZeros
            let power = exponent - fractionDigits + trailingZeros
            guard !negative, power >= 0, count + power <= 19 else { return nil }
            var value = 0
            for index in 0..<(count + power) {
                let digit = index < count ? digits[index] : 0
                let (product, multiplyOverflow) = value.multipliedReportingOverflow(by: 10)
                let (sum, addOverflow) = product.addingReportingOverflow(Int(digit))
                guard !multiplyOverflow, !addOverflow else { return nil }
                value = sum
            }
            return value
        }
    }
}

// Upstream AntigravityLocalSQLiteSchema.swift
import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

#if canImport(SQLite3) || canImport(CSQLite3)
extension AntigravityTokenScanner {
    /// Outcome of a recognized history table's schema inspection.
    enum SQLiteTableSupport {
        /// An ordinary table with the stored columns the payload scan needs.
        case supported
        /// The schema walk completed and described tables, none matching the requested table.
        case foreign
        /// Everything else: a failed inspection, an unreadable schema, or a requested table
        /// whose layout the payload scan does not support.
        case unsupported
    }

    static func inspectSQLiteTableSupport(
        _ database: OpaquePointer,
        table: String = "gen_metadata",
        payloadColumn: String = "data",
        budget: Budget) throws -> SQLiteTableSupport
    {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        // sqlite_master works on older SQLite versions too. Virtual tables and views have no root b-tree page.
        let query = "SELECT name, type, rootpage FROM main.sqlite_master LIMIT ?"
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement else { return .unsupported }
        let cap = min(budget.limits.schemaEntries, 128)
        sqlite3_bind_int64(statement, 1, Int64(cap + 1))
        var entries = 0
        while true {
            try budget.check()
            let step = sqlite3_step(statement)
            // A completed walk over a described schema is evidence, not a failure. An empty database
            // describes nothing and stays unsupported, exactly as a failed inspection does. A walk that
            // the LIMIT truncated never proved the requested table absent, so it stays unsupported too.
            if step == SQLITE_DONE { return entries > 0 && entries <= cap ? .foreign : .unsupported }
            guard step == SQLITE_ROW else { return .unsupported }
            entries += 1
            budget.statistics.schemaEntries += 1
            guard entries <= budget.limits.schemaEntries else { throw ScanFailure.schemaExhausted }
            guard let name = try self.schemaText(statement, column: 0, budget: budget),
                  let type = try self.schemaText(statement, column: 1, budget: budget)
            else { return .unsupported }
            guard name.lowercased() == table else { continue }
            guard type == "table", sqlite3_column_type(statement, 2) == SQLITE_INTEGER,
                  sqlite3_column_int64(statement, 2) > 0 else { return .unsupported }
            return try self.hasStoredSQLiteColumns(
                database, table: table, payloadColumn: payloadColumn, budget: budget) ? .supported : .unsupported
        }
    }

    private static func hasStoredSQLiteColumns(
        _ database: OpaquePointer,
        table: String,
        payloadColumn: String,
        budget: Budget) throws -> Bool
    {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        // table_info omits generated columns. An unknown table_xinfo pragma returns no columns: fail closed.
        guard sqlite3_prepare_v2(database, "PRAGMA main.table_xinfo('\(table)')", -1, &statement, nil) == SQLITE_OK,
              let statement, sqlite3_column_count(statement) >= 7 else { return false }
        var columns = Set<String>()
        var count = 0
        while true {
            try budget.check()
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return columns.isSuperset(of: ["idx", payloadColumn]) }
            guard step == SQLITE_ROW else { return false }
            count += 1
            budget.statistics.schemaColumns += 1
            guard count <= min(budget.limits.schemaColumns, 64) else { throw ScanFailure.schemaExhausted }
            guard sqlite3_column_type(statement, 6) == SQLITE_INTEGER,
                  sqlite3_column_int(statement, 6) == 0 else { return false }
            guard let name = try self.schemaText(statement, column: 1, budget: budget) else { return false }
            _ = try self.schemaText(statement, column: 2, budget: budget)
            _ = try self.schemaText(statement, column: 4, budget: budget)
            columns.insert(name.lowercased())
        }
    }

    private static func schemaText(_ statement: OpaquePointer, column: Int32, budget: Budget) throws -> String? {
        guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
              let pointer = sqlite3_column_text(statement, column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        try budget.chargeSchemaBytes(count)
        return String(bytes: UnsafeBufferPointer(start: pointer, count: count), encoding: .utf8)
    }

    struct SQLitePayload {
        let byteCount: Int
        private let pointer: UnsafeRawPointer?

        init(statement: OpaquePointer) {
            let isBlob = sqlite3_column_type(statement, 2) == SQLITE_BLOB
            self.pointer = isBlob ? sqlite3_column_blob(statement, 2) : nil
            self.byteCount = isBlob ? Int(sqlite3_column_bytes(statement, 2)) : 0
        }

        func copy(declaredCount: Int, limit: Int) -> [UInt8]? {
            guard self.byteCount > 0, self.byteCount == declaredCount, self.byteCount <= limit,
                  let pointer = self.pointer else { return nil }
            // Both pointer and count belong to column 2. Never use a separate SQL expression as a buffer length.
            return Array(UnsafeBufferPointer(start: pointer.assumingMemoryBound(to: UInt8.self), count: self.byteCount))
        }
    }
}
#endif

// Upstream AntigravityLocalSQLite.swift
import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#endif

extension AntigravityTokenScanner {
    static func readDatabases(_ paths: [URL], budget: Budget) throws -> SourceResult {
        var result = SourceResult()
        for url in paths {
            do {
                try budget.check()
                budget.statistics.files += 1
                guard budget.statistics.files <= budget.limits.databases else { throw ScanFailure.exhausted }
                budget.beginDatabase()
                let source = try self.readDatabase(url, budget: budget)
                result.events.append(contentsOf: source.events)
                result.isComplete = result.isComplete && source.isComplete
                result.containsHistorySource = result.containsHistorySource || source.containsHistorySource
                result.evidenceIsUnstable = result.evidenceIsUnstable || source.evidenceIsUnstable
            } catch ScanFailure.schemaExhausted {
                // Schema limits apply to each database, so an oversized schema costs only its own database.
                // Rows from the other databases stay valid partial history. Hard row, byte, and duration
                // limits are not caught here and continue to withhold newly truncated reports as documented.
                result.isComplete = false
            }
        }
        return result
    }

    #if canImport(SQLite3) || canImport(CSQLite3)
    private final class SQLProgress {
        let budget: Budget
        var failure: Error?
        var databaseBytes = 0
        var databaseRows = 0

        var payloadLimit: Int {
            guard self.budget.statistics.rows < self.budget.limits.rows,
                  self.databaseRows < self.budget.limits.rowsPerDatabase else { return 0 }
            return min(
                self.budget.limits.blobBytes,
                self.budget.limits.databaseBytes - self.databaseBytes,
                self.budget.limits.bytes - self.budget.statistics.attemptedBytes)
        }

        init(budget: Budget) {
            self.budget = budget
        }

        func advance() -> Int32 {
            do {
                try self.budget.check()
                return 0
            } catch {
                self.failure = error
                return 1
            }
        }
    }
    #endif

    private enum OpenMode {
        /// Ordinary read-only access with WAL read-mark coordination through the sidecars.
        case readOnly
        /// Lock-free access to the main database file alone. Never creates or touches sidecars.
        case immutable
    }

    private struct DatabaseAttempt {
        let source: SourceResult
        /// SQLite declined the database itself (SQLITE_CANTOPEN) before any row was read.
        let cannotOpen: Bool

        init(_ source: SourceResult, cannotOpen: Bool = false) {
            self.source = source
            self.cannotOpen = cannotOpen
        }
    }

    private static func readDatabase(_ url: URL, budget: Budget) throws -> SourceResult {
        let attempt = try self.readDatabase(url, budget: budget, mode: .readOnly)
        // Some SQLite builds (Apple's system library among them) decline read-only access to a WAL database
        // whose -wal and -shm sidecars are absent, because a read-only connection may not create them.
        // A cleanly closed conversation is exactly that file. An absent -wal also means no WAL connection
        // holds the database, so the main file alone carries the checkpointed state.
        guard attempt.cannotOpen, let before = AntigravityTokenIdleDatabase.read(at: url) else { return attempt.source }
        budget.statistics.immutableFallbacks += 1
        var source = try self.readDatabase(url, budget: budget, mode: .immutable).source
        // An immutable connection neither locks nor detects changes. A writer that appeared during the read
        // could have checkpointed pages into the main file, so the result is trusted only when the file and
        // its sidecar state are unchanged afterwards. Anything else stays incomplete, as before.
        guard AntigravityTokenIdleDatabase.read(at: url) == before else {
            source.isComplete = false
            source.evidenceIsUnstable = true
            return source
        }
        return source
    }

    #if canImport(SQLite3) || canImport(CSQLite3)
    /// Opens the database for the given mode. A failed open leaves no handle behind.
    private static func openDatabase(
        _ url: URL,
        mode: OpenMode,
        budget: Budget) -> (status: Int32, database: OpaquePointer?)
    {
        var database: OpaquePointer?
        let status: Int32 = switch mode {
        case .readOnly:
            sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        case .immutable:
            if let uri = AntigravityTokenIdleDatabase.immutableURI(for: url) {
                sqlite3_open_v2(uri, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
            } else {
                SQLITE_CANTOPEN
            }
        }
        if database != nil {
            budget.statistics.sqliteHandlesOpened += 1
        }
        guard status == SQLITE_OK, let database else {
            if let database, sqlite3_close(database) == SQLITE_OK {
                budget.statistics.sqliteHandlesClosed += 1
            }
            return (status, nil)
        }
        return (status, database)
    }
    #endif

    private static func readDatabase(_ url: URL, budget: Budget, mode: OpenMode) throws -> DatabaseAttempt {
        #if canImport(SQLite3) || canImport(CSQLite3)
        let opened = self.openDatabase(url, mode: mode, budget: budget)
        guard let database = opened.database else {
            return DatabaseAttempt(SourceResult(isComplete: false), cannotOpen: opened.status == SQLITE_CANTOPEN)
        }
        defer {
            if sqlite3_close(database) == SQLITE_OK {
                budget.statistics.sqliteHandlesClosed += 1
            }
        }
        let progress = SQLProgress(budget: budget)
        // Also bound SQLite's own intermediate values, before step can materialize a hostile record/view.
        let maximumValueBytes = min(budget.limits.blobBytes, 64 * 1024 * 1024) + 1024
        sqlite3_limit(database, SQLITE_LIMIT_LENGTH, Int32(min(maximumValueBytes, 64 * 1024)))
        let registered = sqlite3_create_function_v2(
            database,
            "antigravity_payload_limit",
            0,
            SQLITE_UTF8,
            Unmanaged.passUnretained(progress).toOpaque(),
            { context, _, _ in
                guard let context, let pointer = sqlite3_user_data(context) else { return }
                let progress = Unmanaged<SQLProgress>.fromOpaque(pointer).takeUnretainedValue()
                sqlite3_result_int64(context, Int64(progress.payloadLimit))
            },
            nil,
            nil,
            nil)
        guard registered == SQLITE_OK else { return DatabaseAttempt(SourceResult(isComplete: false)) }
        sqlite3_progress_handler(
            database,
            1000,
            { pointer in
                guard let pointer else { return 1 }
                return Unmanaged<SQLProgress>.fromOpaque(pointer).takeUnretainedValue().advance()
            },
            Unmanaged.passUnretained(progress).toOpaque())
        defer {
            withExtendedLifetime(progress) {
                sqlite3_progress_handler(database, 0, nil, nil)
                sqlite3_exec(database, "ROLLBACK", nil, nil, nil)
            }
        }
        // Ordinary read-only SQLite permits WAL read-mark coordination; it does not promise unchanged SHM bytes.
        let began = sqlite3_exec(database, "BEGIN DEFERRED", nil, nil, nil)
        guard began == SQLITE_OK else {
            if let failure = progress.failure {
                throw failure
            }
            return DatabaseAttempt(SourceResult(isComplete: false), cannotOpen: began == SQLITE_CANTOPEN)
        }
        let support = try self.inspectSQLiteTableSupport(database, budget: budget)
        if let failure = progress.failure {
            throw failure
        }
        switch support {
        case .supported:
            break
        case .foreign:
            // A database in a declared root that describes its own tables and no gen_metadata table is not
            // Antigravity history. Skipping it costs no coverage. A gen_metadata table with unknown columns
            // is schema drift, not a foreign file, and stays incomplete on purpose.
            budget.statistics.foreignDatabases += 1
            return DatabaseAttempt(SourceResult())
        case .unsupported:
            // The deferred transaction first touches the file at the schema read, so a declined WAL open
            // surfaces here as a failed prepare and leaves SQLITE_CANTOPEN as the connection's last error.
            return DatabaseAttempt(
                SourceResult(isComplete: false),
                cannotOpen: sqlite3_errcode(database) == SQLITE_CANTOPEN)
        }
        sqlite3_limit(database, SQLITE_LIMIT_LENGTH, Int32(maximumValueBytes))
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        // length(BLOB) reads its size without loading the payload. The non-deterministic limit is
        // evaluated for each row against the remaining job budget, before selecting any payload.
        // No ORDER BY: a sorter could otherwise materialize multiple payloads ahead of accounting.
        let query = """
        SELECT idx, CASE WHEN typeof(data) = 'blob' THEN length(data) END,
            CASE WHEN typeof(data) = 'blob' AND length(data) <= antigravity_payload_limit() THEN data END
        FROM main.gen_metadata NOT INDEXED LIMIT ?
        """
        let prepared = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        if let failure = progress.failure {
            throw failure
        }
        guard prepared == SQLITE_OK, let activeStatement = statement else {
            return DatabaseAttempt(SourceResult(isComplete: false), cannotOpen: prepared == SQLITE_CANTOPEN)
        }
        sqlite3_bind_int64(activeStatement, 1, Int64(min(budget.limits.rowsPerDatabase, 10000) + 1))
        let session = url.deletingPathExtension().lastPathComponent
        var rows = try self.readRows(activeStatement, session: session, progress: progress)
        if !rows.pendingTimestampRows.isEmpty {
            // Positional recovery is safe only when every generation row participated in the occurrence list.
            // A malformed row can still carry a reused step UUID, so partial primary scans must not realign later rows.
            guard rows.source.isComplete else { return DatabaseAttempt(rows.source) }
            // Release the gen_metadata cursor before the optional steps pass reuses the same snapshot.
            sqlite3_finalize(activeStatement)
            statement = nil
            let hasSteps = try self.inspectSQLiteTableSupport(
                database, table: "steps", payloadColumn: "metadata", budget: budget) == .supported
            if let failure = progress.failure {
                throw failure
            }
            if hasSteps {
                var neededStepOccurrences: [String: [StepOccurrence]] = [:]
                for stepUUID in Set(rows.pendingTimestampRows.map(\.stepUUID)) {
                    neededStepOccurrences[stepUUID] = rows.stepOccurrences[stepUUID] ?? []
                }
                let stepScan = try self.readStepTimestamps(
                    database,
                    neededStepOccurrences: neededStepOccurrences,
                    progress: progress)
                guard stepScan.isComplete,
                      self.embeddedTimestampsAgree(neededStepOccurrences, with: stepScan, botIDUses: rows.botIDUses)
                else {
                    rows.source.isComplete = false
                    return DatabaseAttempt(rows.source)
                }
                let recoveredCount = self.appendRecoveredEvents(
                    to: &rows,
                    session: session,
                    stepScan: stepScan)
                if recoveredCount < rows.pendingTimestampRows.count {
                    rows.source.isComplete = false
                }
            } else {
                rows.source.isComplete = false
            }
        }
        return DatabaseAttempt(rows.source)
        #else
        return DatabaseAttempt(SourceResult(isComplete: false))
        #endif
    }

    #if canImport(SQLite3) || canImport(CSQLite3)
    private struct PendingTimestampRow {
        let row: Int64
        let stepUUID: String
        let turn: AntigravityTokenProto.ParsedTurn
    }

    private struct ParsedRows {
        var source: SourceResult
        var pendingTimestampRows: [PendingTimestampRow]
        var stepOccurrences: [String: [StepOccurrence]]
        var botIDUses: [String: Int]
    }

    private struct StepOccurrence {
        let row: Int64
        let timestampMs: Int64?
        let botID: String?
    }

    private struct ExactStepTimestamp {
        let stepUUID: String
        let timestampMs: Int64
    }

    private struct StepTimestampScan {
        let timestamps: [String: [Int64]]
        let byBotID: [String: ExactStepTimestamp]
        let ambiguousBotIDs: Set<String>
        let isComplete: Bool
    }

    private final class StepScanProgress {
        let progress: SQLProgress

        var payloadLimit: Int {
            let budget = self.progress.budget
            guard budget.statistics.rows < budget.limits.rows,
                  self.progress.databaseBytes < budget.limits.databaseBytes,
                  budget.statistics.attemptedBytes < budget.limits.bytes
            else { return 0 }
            return min(
                budget.limits.blobBytes,
                budget.limits.databaseBytes - self.progress.databaseBytes,
                budget.limits.bytes - budget.statistics.attemptedBytes)
        }

        init(progress: SQLProgress) {
            self.progress = progress
        }
    }

    private static func readStepTimestamps(
        _ database: OpaquePointer,
        neededStepOccurrences: [String: [StepOccurrence]],
        progress: SQLProgress) throws -> StepTimestampScan
    {
        guard !neededStepOccurrences.isEmpty else {
            return StepTimestampScan(timestamps: [:], byBotID: [:], ambiguousBotIDs: [], isComplete: true)
        }
        let stepProgress = StepScanProgress(progress: progress)
        let registered = sqlite3_create_function_v2(
            database,
            "antigravity_step_payload_limit",
            0,
            SQLITE_UTF8,
            Unmanaged.passUnretained(stepProgress).toOpaque(),
            { context, _, _ in
                guard let context, let pointer = sqlite3_user_data(context) else { return }
                let progress = Unmanaged<StepScanProgress>.fromOpaque(pointer).takeUnretainedValue()
                sqlite3_result_int64(context, Int64(progress.payloadLimit))
            },
            nil,
            nil,
            nil)
        guard registered == SQLITE_OK else {
            return StepTimestampScan(timestamps: [:], byBotID: [:], ambiguousBotIDs: [], isComplete: false)
        }
        var statement: OpaquePointer?
        defer {
            withExtendedLifetime(stepProgress) {
                sqlite3_finalize(statement)
                sqlite3_create_function_v2(
                    database,
                    "antigravity_step_payload_limit",
                    0,
                    SQLITE_UTF8,
                    nil,
                    nil,
                    nil,
                    nil,
                    nil)
            }
        }
        let query = """
        SELECT idx, CASE WHEN typeof(metadata) = 'blob' THEN length(metadata) END,
            CASE WHEN typeof(metadata) = 'blob'
                AND length(metadata) <= antigravity_step_payload_limit() THEN metadata END
        FROM main.steps NOT INDEXED
        """
        let prepared = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        if let failure = progress.failure {
            throw failure
        }
        guard prepared == SQLITE_OK, let statement else {
            return StepTimestampScan(timestamps: [:], byBotID: [:], ambiguousBotIDs: [], isComplete: false)
        }
        var stepTimestamps: [String: [StepOccurrence]] = [:]
        var exactByBotID: [String: ExactStepTimestamp] = [:]
        var ambiguousBotIDs = Set<String>()
        var isComplete = false
        var rowsAreValid = true
        var sawUnidentifiedRows = false
        while true {
            try progress.budget.check()
            let step = sqlite3_step(statement)
            if let failure = progress.failure {
                throw failure
            }
            if step == SQLITE_DONE {
                isComplete = true
                break
            }
            guard step == SQLITE_ROW else { break }
            let payload = SQLitePayload(statement: statement)
            progress.budget.statistics.materializedPayloadBytes += payload.byteCount
            // Every secondary row belongs to the job-wide budget; the separate byte ceiling only
            // prevents one database's step metadata from consuming the whole job allocation.
            try progress.budget.chargeRow()
            let count = Int(sqlite3_column_int64(statement, 1))
            let attemptedBytes = max(count, payload.byteCount)
            try progress.budget.chargeBytes(attemptedBytes)
            guard attemptedBytes <= progress.budget.limits.databaseBytes - progress.databaseBytes
            else { throw ScanFailure.exhausted }
            progress.databaseBytes += attemptedBytes
            guard count > 0, count <= progress.budget.limits.blobBytes,
                  sqlite3_column_type(statement, 0) == SQLITE_INTEGER,
                  sqlite3_column_int64(statement, 0) >= 0,
                  let bytes = payload.copy(declaredCount: count, limit: progress.budget.limits.blobBytes)
            else {
                rowsAreValid = false
                continue
            }
            guard let parsed = try AntigravityTokenProto.parseStepMetadata(
                bytes, checkCancellation: progress.budget.check)
            else {
                rowsAreValid = false
                continue
            }
            if let botID = parsed.botID {
                self.recordExactBotID(
                    botID,
                    stepUUID: parsed.stepUUID,
                    timestampMs: parsed.timestampMs,
                    exact: &exactByBotID,
                    ambiguous: &ambiguousBotIDs)
            }
            // Unidentified rows cannot supply UUID positions, but their bot IDs still count as evidence.
            guard let stepUUID = parsed.stepUUID else {
                sawUnidentifiedRows = true
                continue
            }
            if neededStepOccurrences[stepUUID] != nil {
                stepTimestamps[stepUUID, default: []].append(StepOccurrence(
                    row: sqlite3_column_int64(statement, 0),
                    timestampMs: parsed.timestampMs,
                    botID: parsed.botID))
            }
        }
        let resolved = self.resolveStepTimestamps(
            stepTimestamps,
            neededStepOccurrences: neededStepOccurrences,
            ambiguousBotIDs: ambiguousBotIDs,
            unidentifiedRowsPresent: sawUnidentifiedRows)
        return StepTimestampScan(
            timestamps: resolved,
            byBotID: exactByBotID,
            ambiguousBotIDs: ambiguousBotIDs,
            isComplete: isComplete && rowsAreValid)
    }

    private static func recordExactBotID(
        _ botID: String,
        stepUUID: String?,
        timestampMs: Int64?,
        exact: inout [String: ExactStepTimestamp],
        ambiguous: inout Set<String>)
    {
        guard !ambiguous.contains(botID) else { return }
        guard let stepUUID, let timestampMs else {
            exact.removeValue(forKey: botID)
            ambiguous.insert(botID)
            return
        }
        if let existing = exact[botID] {
            if existing.timestampMs != timestampMs || existing.stepUUID != stepUUID {
                exact.removeValue(forKey: botID)
                ambiguous.insert(botID)
            }
        } else {
            exact[botID] = ExactStepTimestamp(stepUUID: stepUUID, timestampMs: timestampMs)
        }
    }

    private static func embeddedTimestampsAgree(
        _ occurrences: [String: [StepOccurrence]],
        with stepScan: StepTimestampScan,
        botIDUses: [String: Int]) -> Bool
    {
        for (stepUUID, rows) in occurrences {
            for row in rows {
                guard let timestampMs = row.timestampMs, let botID = row.botID else { continue }
                guard !stepScan.ambiguousBotIDs.contains(botID) else { return false }
                if let exact = stepScan.byBotID[botID],
                   exact.stepUUID != stepUUID || (botIDUses[botID] == 1 && exact.timestampMs != timestampMs)
                {
                    return false
                }
            }
        }
        return true
    }

    private static func resolveStepTimestamps(
        _ stepTimestamps: [String: [StepOccurrence]],
        neededStepOccurrences: [String: [StepOccurrence]],
        ambiguousBotIDs: Set<String>,
        unidentifiedRowsPresent: Bool) -> [String: [Int64]]
    {
        var resolved: [String: [Int64]] = [:]
        for (stepUUID, timestamps) in stepTimestamps {
            guard let occurrences = neededStepOccurrences[stepUUID] else { continue }
            let sortedOccurrences = occurrences.sorted { $0.row < $1.row }
            guard Set(sortedOccurrences.map(\.row)).count == sortedOccurrences.count else { continue }
            let neededCount = sortedOccurrences.count
            let sorted = timestamps.sorted { $0.row < $1.row }
            // The defensive schema does not require idx to be a key. Conflicting duplicate indices
            // cannot be ordered safely, so withhold that UUID instead of publishing a false date.
            guard !zip(sorted, sorted.dropFirst()).contains(where: { pair in pair.0.row == pair.1.row }) else {
                continue
            }
            // Keep ambiguous slots so later timestamps cannot slide into their positions.
            let orderedTimestamps = sorted.map { step in
                step.botID.map { ambiguousBotIDs.contains($0) } == true ? nil : step.timestampMs
            }
            let selected: [Int64]
            // Sharing one timestamp across reused UUIDs requires a complete identity census.
            if orderedTimestamps.count == 1, neededCount == 1 || !unidentifiedRowsPresent,
               let sharedTimestamp = orderedTimestamps[0]
            {
                selected = Array(repeating: sharedTimestamp, count: neededCount)
            } else {
                guard orderedTimestamps.count >= neededCount else { continue }
                let candidates = orderedTimestamps.prefix(neededCount)
                guard candidates.allSatisfy({ $0 != nil }) else { continue }
                selected = candidates.compactMap(\.self)
            }
            guard zip(sortedOccurrences, selected).allSatisfy({ pair in
                pair.0.timestampMs == nil || pair.0.timestampMs == pair.1
            }) else { continue }
            resolved[stepUUID] = selected
        }
        return resolved
    }

    private static func readRows(
        _ statement: OpaquePointer,
        session: String,
        progress: SQLProgress) throws -> ParsedRows
    {
        let budget = progress.budget
        var result = SourceResult(containsHistorySource: true)
        var pendingTimestampRows: [PendingTimestampRow] = []
        var stepOccurrences: [String: [StepOccurrence]] = [:]
        var botIDUses: [String: Int] = [:]
        while true {
            try budget.check()
            let step = sqlite3_step(statement)
            if let failure = progress.failure {
                throw failure
            }
            if step == SQLITE_DONE {
                break
            }
            guard step == SQLITE_ROW else {
                result.isComplete = false
                break
            }
            let payload = SQLitePayload(statement: statement)
            budget.statistics.materializedPayloadBytes += payload.byteCount
            progress.databaseRows += 1
            try budget.chargeRow()
            // Count every row, even NULL/empty records, and charge rejected bytes before another attempt.
            let count = Int(sqlite3_column_int64(statement, 1))
            let attemptedBytes = max(count, payload.byteCount)
            try budget.chargeBytes(attemptedBytes)
            guard progress.databaseRows <= budget.limits.rowsPerDatabase,
                  attemptedBytes <= budget.limits.databaseBytes - progress.databaseBytes
            else {
                throw ScanFailure.exhausted
            }
            progress.databaseBytes += attemptedBytes
            guard count > 0, count <= budget.limits.blobBytes,
                  sqlite3_column_type(statement, 0) == SQLITE_INTEGER
            else {
                result.isComplete = false
                continue
            }
            let row = sqlite3_column_int64(statement, 0)
            guard row >= 0 else {
                result.isComplete = false
                continue
            }
            guard let bytes = payload.copy(declaredCount: count, limit: budget.limits.blobBytes) else {
                result.isComplete = false
                continue
            }
            // Validate exactly once while the single SQL snapshot is held; buffer only typed events.
            guard let turn = try AntigravityTokenProto.parseTurn(bytes, checkCancellation: budget.check) else {
                result.isComplete = false
                continue
            }
            if let botID = turn.usage?.botID {
                botIDUses[botID, default: 0] += 1
            }
            if let stepUUID = turn.stepUUID {
                stepOccurrences[stepUUID, default: []].append(StepOccurrence(
                    row: row,
                    timestampMs: turn.timestampMs,
                    botID: turn.usage?.botID))
            }
            if turn.timestampMs == nil, let stepUUID = turn.stepUUID {
                pendingTimestampRows.append(PendingTimestampRow(
                    row: row, stepUUID: stepUUID, turn: turn))
                continue
            }
            guard let event = Event(session: session, row: row, turn: turn, cacheWrite: 0) else {
                result.isComplete = false
                continue
            }
            result.events.append(event)
        }
        return ParsedRows(
            source: result,
            pendingTimestampRows: pendingTimestampRows,
            stepOccurrences: stepOccurrences,
            botIDUses: botIDUses)
    }

    private static func appendRecoveredEvents(
        to rows: inout ParsedRows,
        session: String,
        stepScan: StepTimestampScan) -> Int
    {
        var occurrenceOffsets: [String: [Int64: Int]] = [:]
        for (stepUUID, occurrences) in rows.stepOccurrences {
            let sorted = occurrences.map(\.row).sorted()
            guard Set(sorted).count == sorted.count else { continue }
            occurrenceOffsets[stepUUID] = Dictionary(
                uniqueKeysWithValues: sorted.enumerated().map { ($0.element, $0.offset) })
        }
        var recoveredCount = 0
        for pending in rows.pendingTimestampRows.sorted(by: { $0.row < $1.row }) {
            if let botID = pending.turn.usage?.botID {
                if stepScan.ambiguousBotIDs.contains(botID) {
                    // Conflicting step timestamps for one bot ID: withhold rather than guess.
                    continue
                }
                if let exact = stepScan.byBotID[botID] {
                    guard exact.stepUUID == pending.stepUUID else { continue }
                }
                // All generations participate, including rows with an embedded timestamp.
                if rows.botIDUses[botID] == 1, let exact = stepScan.byBotID[botID] {
                    var turn = pending.turn
                    turn.timestampMs = exact.timestampMs
                    if let event = Event(session: session, row: pending.row, turn: turn, cacheWrite: 0) {
                        rows.source.events.append(event)
                        recoveredCount += 1
                    }
                    continue
                }
            }
            guard let timestamps = stepScan.timestamps[pending.stepUUID],
                  let offset = occurrenceOffsets[pending.stepUUID]?[pending.row]
            else {
                continue
            }
            guard timestamps.indices.contains(offset) else { continue }
            var turn = pending.turn
            turn.timestampMs = timestamps[offset]
            if let event = Event(session: session, row: pending.row, turn: turn, cacheWrite: 0) {
                rows.source.events.append(event)
                recoveredCount += 1
            }
        }
        rows.source.events.sort { $0.row < $1.row }
        return recoveredCount
    }
    #endif
}

// Upstream AntigravityLocalJSONL.swift
import Foundation

extension AntigravityTokenScanner {
    private struct JSONLSession {
        var id: String?
        var model: String?
        var line: Int64 = 0
    }

    static func readJSONL(_ paths: [URL], budget: Budget) throws -> SourceResult {
        var result = SourceResult()
        for url in paths {
            try budget.check()
            budget.statistics.files += 1
            guard budget.statistics.files <= budget.limits.databases else { throw ScanFailure.exhausted }
            let source = try self.readJSONLFile(url, budget: budget)
            result.events.append(contentsOf: source.events)
            result.isComplete = result.isComplete && source.isComplete
            result.containsHistorySource = result.containsHistorySource || source.containsHistorySource
        }
        return result
    }

    private static func readJSONLFile(_ url: URL, budget: Budget) throws -> SourceResult {
        let values: URLResourceValues
        do {
            values = try url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            return SourceResult(isComplete: false)
        }
        guard values.isRegularFile == true, let size = values.fileSize else {
            return SourceResult(isComplete: false)
        }
        // Check the known size before allocation; streaming also handles a file that grows after this check.
        if size > budget.limits.databaseBytes || size > budget.limits.bytes - budget.statistics.attemptedBytes {
            try budget.chargeBytes(size)
            throw ScanFailure.exhausted
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            return SourceResult(isComplete: false)
        }
        defer { try? handle.close() }
        var result = SourceResult()
        var session = JSONLSession()
        var line: [UInt8] = []
        var fileBytes = 0
        while true {
            try budget.check()
            let remaining = min(
                budget.limits.databaseBytes - fileBytes,
                budget.limits.bytes - budget.statistics.attemptedBytes)
            let chunk: Data
            do {
                chunk = try handle.read(upToCount: min(65536, remaining + 1)) ?? Data()
            } catch {
                result.isComplete = false
                break
            }
            if chunk.isEmpty { break }
            try budget.chargeBytes(chunk.count)
            fileBytes += chunk.count
            guard fileBytes <= budget.limits.databaseBytes else { throw ScanFailure.exhausted }
            for (index, byte) in chunk.enumerated() {
                if index % 4096 == 0 { try budget.check() }
                if byte == 10 {
                    try self.consumeJSONLLine(line, session: &session, result: &result, budget: budget)
                    line.removeAll(keepingCapacity: true)
                } else {
                    guard line.count < budget.limits.blobBytes else { throw ScanFailure.exhausted }
                    line.append(byte)
                }
            }
        }
        if !line.isEmpty {
            try self.consumeJSONLLine(line, session: &session, result: &result, budget: budget)
        }
        result.containsHistorySource = session.id != nil
        if session.id == nil { result.isComplete = false }
        return result
    }

    private static func consumeJSONLLine(
        _ line: [UInt8],
        session: inout JSONLSession,
        result: inout SourceResult,
        budget: Budget) throws
    {
        try budget.chargeRow()
        session.line += 1
        guard session.line <= budget.limits.rowsPerDatabase else { throw ScanFailure.exhausted }
        if line.allSatisfy({ $0 == 13 || $0 == 32 || $0 == 9 }) { return }
        guard let json = try AntigravityTokenJSON.decode(line, checkCancellation: budget.check) else {
            result.isComplete = false
            return
        }
        do {
            guard let type = json["type"] as? String else { throw ScanFailure.invalid }
            if type == "session_meta" {
                let id = try self.optionalString(json, keys: ["sessionId"])
                guard let id, session.id == nil || session.id == id else { throw ScanFailure.invalid }
                session.id = id
                session.model = try self.optionalString(json, keys: ["modelId", "model_id"])
                return
            }
            guard type == "usage" else { throw ScanFailure.invalid }
            let id = try self.optionalString(json, keys: ["sessionId"]) ?? session.id
            guard let id, session.id == nil || session.id == id,
                  let timestamp = try self.optionalTimestamp(json["timestamp"]) else { throw ScanFailure.invalid }
            var usage = AntigravityTokenProto.ParsedUsage()
            usage.newInput = try self.jsonCounter(json, keys: ["input"], required: true)
            usage.output = try self.jsonCounter(json, keys: ["output"], required: true)
            usage.cacheRead = try self.jsonCounter(json, keys: ["cacheRead", "cache_read"])
            usage.reasoning = try self.jsonCounter(json, keys: ["reasoning"])
            // The producer names both counters but does not establish their overlap. Do not guess an exact total.
            guard usage.reasoning == 0 else { throw ScanFailure.invalid }
            usage.responseID = try self.optionalString(json, keys: ["responseId", "response_id"])
            let write = try self.jsonCounter(json, keys: ["cacheWrite", "cache_write"])
            let model = try self.optionalString(json, keys: ["modelId", "model_id"]) ?? session.model
            let turn = AntigravityTokenProto.ParsedTurn(usage: usage, timestampMs: timestamp, model: model)
            guard let event = Event(session: id, row: session.line, turn: turn, cacheWrite: write) else {
                throw ScanFailure.invalid
            }
            session.id = id
            result.events.append(event)
        } catch {
            result.isComplete = false
        }
    }

    private static func exactInteger(_ value: Any) throws -> Int {
        guard let integer = (value as? AntigravityTokenJSON.Number)?.integer else {
            throw ScanFailure.invalid
        }
        return integer
    }

    private static func jsonCounter(_ json: [String: Any], keys: [String], required: Bool = false) throws -> Int {
        var counter: Int?
        for key in keys {
            guard let value = json[key] else { continue }
            let integer = try self.exactInteger(value)
            guard integer >= 0, counter == nil || counter == integer else { throw ScanFailure.invalid }
            counter = integer
        }
        guard !required || counter != nil else { throw ScanFailure.invalid }
        return counter ?? 0
    }

    private static func optionalString(_ json: [String: Any], keys: [String]) throws -> String? {
        var text: String?
        for key in keys {
            guard let value = json[key], !(value is NSNull) else { continue }
            guard let value = value as? String else { throw ScanFailure.invalid }
            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
            guard text == nil || text == value else { throw ScanFailure.invalid }
            text = value
        }
        return text
    }

    private static func optionalTimestamp(_ value: Any?) throws -> Int64? {
        guard let value, !(value is NSNull) else { return nil }
        let timestamp = try self.exactInteger(value)
        guard timestamp > 0, timestamp <= 253_402_300_799_999 else { throw ScanFailure.invalid }
        return Int64(timestamp)
    }
}

import Foundation

/// Identity of an idle WAL database: no `-wal` sidecar, plus the main file's size, modification
/// time, file system number, and 100-byte header. Nil when a `-wal` sidecar exists or the file
/// cannot be examined.
struct AntigravityTokenIdleDatabase: Equatable {
    let size: UInt64
    let modified: Date
    let fileNumber: UInt64
    let header: Data

    static func read(at url: URL) -> Self? {
        // SQLite places sidecars next to the resolved database file, not next to a symlink.
        let resolved = url.resolvingSymlinksInPath()
        guard !FileManager.default.fileExists(atPath: resolved.path + "-wal"),
              let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date,
              let fileNumber = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let handle = try? FileHandle(forReadingFrom: resolved)
        else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 100) else { return nil }
        return Self(size: size, modified: modified, fileNumber: fileNumber, header: header)
    }

    /// The `immutable=1` query parameter is only reachable through a URI filename.
    static func immutableURI(for url: URL) -> String? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "%?#")
        guard let path = url.path.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return "file:\(path)?immutable=1"
    }
}

enum AntigravityTokenSum {
    /// Empty input sums to zero. Missing-value policy belongs to the caller; any overflow
    /// invalidates the entire sum, even if later values would bring it back into range.
    static func integers(_ values: some Sequence<Int>) -> Int? {
        var total = 0
        for value in values {
            let addition = total.addingReportingOverflow(value)
            guard !addition.overflow else { return nil }
            total = addition.partialValue
        }
        return total
    }
}

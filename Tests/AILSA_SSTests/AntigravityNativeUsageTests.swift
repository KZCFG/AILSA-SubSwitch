// Synthetic protobuf/SQLite fixtures adapted from CodexBar v0.81.0; MIT, Peter Steinberger.
import Foundation
import SQLite3
import XCTest
@testable import AILSA_SS

private enum NativeTokenFixture {
    static func open(_ url: URL) throws -> OpaquePointer {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard result == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            throw AntigravityTokenScanner.ScanFailure.invalid
        }
        return database
    }

    static func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw AntigravityTokenScanner.ScanFailure.invalid
        }
    }

    static func insert(_ database: OpaquePointer, row: Int64, blob: [UInt8]) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(
            database, "INSERT INTO gen_metadata (idx, data) VALUES (?, ?)", -1, &statement, nil) == SQLITE_OK
        else { throw AntigravityTokenScanner.ScanFailure.invalid }
        sqlite3_bind_int64(statement, 1, row)
        let result = blob.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(blob.count), nil)
            return sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw AntigravityTokenScanner.ScanFailure.invalid }
    }

    static func insertStep(_ database: OpaquePointer, row: Int64, blob: [UInt8]) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(
            database, "INSERT INTO steps (idx, metadata) VALUES (?, ?)", -1, &statement, nil) == SQLITE_OK
        else { throw AntigravityTokenScanner.ScanFailure.invalid }
        sqlite3_bind_int64(statement, 1, row)
        let result = blob.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 2, bytes.baseAddress, Int32(blob.count), nil)
            return sqlite3_step(statement)
        }
        guard result == SQLITE_DONE else { throw AntigravityTokenScanner.ScanFailure.invalid }
    }

    static func varint(_ field: Int, _ value: UInt64) -> [UInt8] {
        self.unsigned(UInt64(field << 3)) + self.unsigned(value)
    }

    static func message(_ field: Int, _ bytes: [UInt8]) -> [UInt8] {
        self.unsigned(UInt64(field << 3 | 2)) + self.unsigned(UInt64(bytes.count)) + bytes
    }

    private static func unsigned(_ value: UInt64) -> [UInt8] {
        var value = value
        var bytes: [UInt8] = []
        while value >= 128 {
            bytes.append(UInt8(value & 127) | 128)
            value >>= 7
        }
        bytes.append(UInt8(value))
        return bytes
    }

    static func blob(
        model: String? = "fixture-model-a",
        label: String? = "Fixture model",
        modelID: UInt64 = 1298,
        input: UInt64 = 100,
        output: UInt64 = 30,
        cacheRead: UInt64 = 50,
        reasoning: UInt64 = 7,
        response: String? = nil,
        seconds: UInt64? = 1_787_832_000) -> [UInt8]
    {
        var usage = self.varint(1, modelID) + self.varint(2, input) + self.varint(5, cacheRead)
            + self.varint(9, reasoning) + self.varint(10, output)
        if let response {
            usage += self.message(11, Array(response.utf8))
        }
        var chat = self.message(4, usage)
        if let seconds {
            chat += self.message(9, self.message(4, self.varint(1, seconds) + self.varint(2, 250_000_000)))
        }
        if let model {
            chat += self.message(19, Array(model.utf8))
        }
        if let label {
            chat += self.message(21, Array(label.utf8))
        }
        return self.message(1, chat)
    }

    static func blobWithRootEnvelope(
        stepUUID: String? = "step-uuid-1",
        botID: String? = nil,
        model: String? = "fixture-model-a",
        label: String? = "Fixture model",
        modelID: UInt64 = 1298,
        input: UInt64 = 100,
        output: UInt64 = 30,
        cacheRead: UInt64 = 50,
        reasoning: UInt64 = 7,
        response: String? = nil,
        seconds: UInt64? = nil) -> [UInt8]
    {
        var root = self.message(2, [0x01, 0x02])
        if let stepUUID {
            root += self.message(4, Array(stepUUID.utf8))
        }
        var usage = self.varint(1, modelID) + self.varint(2, input) + self.varint(5, cacheRead)
            + self.varint(9, reasoning) + self.varint(10, output)
        if let botID {
            usage += self.message(7, Array(botID.utf8))
        }
        if let response {
            usage += self.message(11, Array(response.utf8))
        }
        var chat = self.message(4, usage)
        if let seconds {
            chat += self.message(9, self.message(4, self.varint(1, seconds) + self.varint(2, 250_000_000)))
        }
        if let model {
            chat += self.message(19, Array(model.utf8))
        }
        if let label {
            chat += self.message(21, Array(label.utf8))
        }
        root += self.message(1, chat)
        return root
    }

    static func stepMetadataBlob(
        stepUUID: String? = "step-uuid-1",
        botID: String? = nil,
        seconds: UInt64 = 1_787_832_000,
        nanos: UInt64 = 250_000_000) -> [UInt8]
    {
        var meta = self.message(1, self.varint(1, seconds) + self.varint(2, nanos))
        if let botID {
            let usage = self.message(7, Array(botID.utf8))
            meta += self.message(9, usage)
        }
        if let stepUUID {
            meta += self.message(12, Array(stepUUID.utf8))
        }
        return meta
    }

}

final class AntigravityNativeUsageTests: XCTestCase {
    private typealias F = NativeTokenFixture
    private let stamp: UInt64 = 1_787_832_000
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        addTeardownBlock { try? FileManager.default.removeItem(at:url) }; return url
    }
    @discardableResult private func db(_ root:URL, _ name:String = "session", blobs:[[UInt8]], steps:[[UInt8]] = []) throws -> URL {
        let url = root.appendingPathComponent(name+".db"), handle = try F.open(url)
        defer { sqlite3_close(handle) }
        try F.execute(handle,"CREATE TABLE gen_metadata (idx INTEGER PRIMARY KEY,data BLOB)")
        for (i,b) in blobs.enumerated() { try F.insert(handle,row:Int64(i),blob:b) }
        if !steps.isEmpty {
            try F.execute(handle,"CREATE TABLE steps (idx INTEGER PRIMARY KEY,metadata BLOB)")
            for (i,b) in steps.enumerated() { try F.insertStep(handle,row:Int64(i),blob:b) }
        }; return url
    }
    private func read(_ root:URL, limits:AntigravityTokenScanner.Limits = .init()) throws -> AntigravityTokenUsage {
        var reader = AntigravityTokenUsageReader(); return try reader.read(roots:[root],cacheRoot:nil,limits:limits)
    }
    private func empty(_ now:Date) -> QuotaDashboardSnapshot {
        QuotaDashboardSnapshot.compact([String:QuotaContribution]().values,discarded:0,now:now)
    }
    func testDisjointCountersAndModelEnumNeverCounted() throws {
        let r=try root(); try db(r,blobs:[F.blob(model:"gemini-3.8-flash",modelID:1318,input:100,output:30,cacheRead:50,reasoning:7)])
        let value=try XCTUnwrap(read(r).entries.first?.contribution.value)
        XCTAssertEqual(value.tokens.input,150); XCTAssertEqual(value.tokens.cachedInput,50)
        XCTAssertEqual(value.tokens.output,37); XCTAssertEqual(value.tokens.reasoningOutput,7)
        XCTAssertEqual(value.tokens.total,187); XCTAssertEqual(value.reported,1)
        XCTAssertEqual(value.reference.count,1)
    }
    func testBotJoinRecoversTimeDespiteExtraAndReversedSteps() throws {
        let r=try root()
        try db(r,blobs:[F.blobWithRootEnvelope(botID:"a",model:"gemini-3.8-flash"),F.blobWithRootEnvelope(botID:"b",model:"gemini-3.8-flash")],steps:[F.stepMetadataBlob(botID:"b",seconds:stamp+86400),F.stepMetadataBlob(botID:"inflight",seconds:stamp+100),F.stepMetadataBlob(botID:"a",seconds:stamp)])
        let result=try read(r)
        XCTAssertEqual(result.entries.count,2); XCTAssertFalse(result.diagnostics.partial)
        XCTAssertEqual(Set(result.entries.map{$0.contribution.day}),Set([Calendar.current.startOfDay(for:Date(timeIntervalSince1970:Double(stamp))),Calendar.current.startOfDay(for:Date(timeIntervalSince1970:Double(stamp+86400)))]))
    }
    func testMissingTimeIsWithheldNeverInferredFromFileDate() throws {
        let r=try root(); try db(r,blobs:[F.blob(seconds:nil)])
        let result=try read(r); XCTAssertTrue(result.entries.isEmpty); XCTAssertTrue(result.diagnostics.partial)
    }
    func testEmbeddedTimeWinsAndConflictingBotJoinFailsClosed() throws {
        let r=try root(); try db(r,blobs:[F.blobWithRootEnvelope(botID:"a",seconds:stamp)],steps:[F.stepMetadataBlob(botID:"a",seconds:stamp+86400)])
        XCTAssertEqual(try read(r).entries.first?.contribution.day,Calendar.current.startOfDay(for:Date(timeIntervalSince1970:Double(stamp))))
        let bad=try root(); try db(bad,blobs:[F.blobWithRootEnvelope(botID:"a")],steps:[F.stepMetadataBlob(botID:"a",seconds:stamp),F.stepMetadataBlob(botID:"a",seconds:stamp+86400)])
        XCTAssertTrue(try read(bad).entries.isEmpty); XCTAssertTrue(try read(bad).diagnostics.partial)
    }
    func testCopiesDedupAndConflictingRowsAreWithheld() throws {
        let a=try root(),b=try root();let url=try db(a,blobs:[F.blob(response:"one")]);try FileManager.default.copyItem(at:url,to:b.appendingPathComponent("session.db"))
        var reader=AntigravityTokenUsageReader(); let identical=try reader.read(roots:[a,b],cacheRoot:nil)
        XCTAssertEqual(identical.entries.count,1);XCTAssertEqual(identical.diagnostics.duplicates,1)
        let handle=try F.open(b.appendingPathComponent("session.db"));defer{sqlite3_close(handle)}
        try F.execute(handle,"DELETE FROM gen_metadata");try F.insert(handle,row:0,blob:F.blob(input:101,response:"one"))
        let conflict=try reader.read(roots:[a,b],cacheRoot:nil)
        XCTAssertTrue(conflict.entries.isEmpty);XCTAssertTrue(conflict.diagnostics.partial)
    }
    func testResponseDuplicatesAcrossSessionsButNotSimilarRequests() throws {
        let r=try root();try db(r,"one",blobs:[F.blob(response:"same"),F.blob(response:"different")]);try db(r,"two",blobs:[F.blob(response:"same")])
        let result=try read(r);XCTAssertEqual(result.entries.count,2);XCTAssertEqual(result.diagnostics.duplicates,1)
    }
    func testNativeLedgerOverlapUsesExactResponseAndGeminiFamily() throws {
        let r=try root();try db(r,blobs:[F.blob(model:"gemini-3.8-flash-n",response:"shared"),F.blob(model:"gemini-3.8-flash",response:"distinct")])
        let native=try read(r), now=Date(timeIntervalSince1970:Double(stamp))
        var base=empty(now);base.providerResponseKeys=[try XCTUnwrap(AntigravityTokenUsage.responseKey(model:"gemini-3.8-flash",responseID:"shared"))]
        let merged=native.merging(into:base,now:now,historyDays:30)
        XCTAssertEqual(merged.all.tokens.total,187);XCTAssertEqual(merged.antigravityTokenUsage?.overlaps,1)
        XCTAssertEqual(QuotaModelKey(provider:"google-antigravity",model:"gemini-3.8-flash-n").familyKey,QuotaModelKey(provider:"antigravity-pool",model:"gemini-3.8-flash").familyKey)
    }
    func testRangeAndMinuteRebuildFromCachedEvents() throws {
        let r=try root();try db(r,blobs:[F.blob(seconds:stamp),F.blob(seconds:stamp-40*86400)])
        var reader=AntigravityTokenUsageReader();let native=try reader.read(roots:[r],cacheRoot:nil)
        let now=Date(timeIntervalSince1970:Double(stamp)), short=native.merging(into:empty(now),now:now,historyDays:30),long=native.merging(into:empty(now),now:now,historyDays:90)
        XCTAssertEqual(short.days.count,1);XCTAssertEqual(long.days.count,2);XCTAssertEqual(short.all.tokens.total,374)
        XCTAssertEqual(short.minuteTokens.values.reduce(0,+),187)
        let cached=try reader.read(roots:[r],cacheRoot:nil);XCTAssertEqual(cached.diagnostics.cacheHits,1)
    }
    func testLiveWALUpdateInvalidatesCache() throws {
        let r=try root(), url=try db(r,blobs:[F.blob()]); let handle=try F.open(url);defer{sqlite3_close(handle)}
        try F.execute(handle,"PRAGMA journal_mode=WAL");try F.execute(handle,"PRAGMA wal_autocheckpoint=0")
        var reader=AntigravityTokenUsageReader();XCTAssertEqual(try reader.read(roots:[r],cacheRoot:nil).entries.count,1)
        try F.insert(handle,row:1,blob:F.blob(response:"new"))
        XCTAssertEqual(try reader.read(roots:[r],cacheRoot:nil).entries.count,2)
    }
    func testUnknownModelRemainsAuditableNotExportable() throws {
        let r=try root();try db(r,blobs:[F.blob(model:nil,label:nil)])
        let entry=try XCTUnwrap(read(r).entries.first);XCTAssertEqual(entry.contribution.value.tokens.total,187)
        XCTAssertFalse(entry.contribution.key.hasIdentifiedModel);XCTAssertEqual(entry.contribution.value.unknownRoute,1)
    }
    func testForeignSummaryIsSkippedWithoutPoisoningCoverage() throws {
        let r=try root();try db(r,blobs:[F.blob()]);let handle=try F.open(r.appendingPathComponent("summary.db"));defer{sqlite3_close(handle)}
        try F.execute(handle,"CREATE TABLE summaries (text TEXT)")
        let native=try read(r);XCTAssertEqual(native.entries.count,1);XCTAssertFalse(native.diagnostics.partial)
    }
    func testMalformedAndBoundedScanNeverPublishInventedCounts() throws {
        let r=try root();try db(r,blobs:[[0xff],F.blob()]);let native=try read(r)
        XCTAssertEqual(native.entries.count,1);XCTAssertTrue(native.diagnostics.partial)
        var limits=AntigravityTokenScanner.Limits();limits.rows=0
        let bounded=try read(r,limits:limits);XCTAssertTrue(bounded.entries.isEmpty);XCTAssertTrue(bounded.diagnostics.unavailable)
    }
    func testSymlinkOutsideDeclaredRootIsNotRead() throws {
        let r=try root(), outside=try root(), url=try db(outside,blobs:[F.blob()])
        try FileManager.default.createSymbolicLink(at:r.appendingPathComponent("linked.db"),withDestinationURL:url)
        XCTAssertTrue(try read(r).entries.isEmpty)
    }
    func testServiceLedgerPathMergesNativeUsageAndKeepsAccountsIndependent() async throws {
        let r=try root();try db(r,blobs:[F.blob(model:"gemini-3.8-flash")])
        let ledger=r.appendingPathComponent("usage.jsonl")
        let record:[String:Any] = ["requestId":"ledger-one","timestamp":"2026-08-27T12:00:00Z","provider":"antigravity-pool","resolvedModel":"gemini-3.8-flash","usageStatus":"reported","usage":["inputTokens":100,"outputTokens":20,"totalTokens":120]]
        try (JSONSerialization.data(withJSONObject:record)+Data([10])).write(to:ledger)
        let missing=r.appendingPathComponent("missing")
        var paths=QuotaManagementDataPaths(codexSessionsDirectory:missing,codexArchivedSessionsDirectory:missing,codexBarPricingCatalogURL:missing,opencodexUsageLedgerURL:ledger,antigravityQuotaHistoryURL:missing,antigravityInfoPlistURL:missing);paths.antigravityConversationDirectories=[r]
        let service=LocalQuotaManagementUsageService(paths:paths), now=Date(timeIntervalSince1970:Double(stamp))
        let dashboard=try await service.loadDashboard(for:.codex,now:now)
        XCTAssertEqual(dashboard.all.tokens.total,307);XCTAssertEqual(dashboard.antigravityTokenUsage?.requests,1)
        XCTAssertEqual(dashboard.bucket(from:Calendar.current.startOfDay(for:now),until:now.addingTimeInterval(86400)).total.tokens.total,307)
    }
    func testLedgerResponseIdentityFlowsThroughBothSnapshotBuilders() throws {
        let r=try root(),ledger=r.appendingPathComponent("usage.jsonl")
        let record:[String:Any] = ["requestId":"one","upstreamResponseId":"response-one","timestamp":"2026-08-27T12:00:00Z","provider":"antigravity-pool","resolvedModel":"gemini-3.8-flash","usageStatus":"reported","usage":["inputTokens":100,"outputTokens":20,"totalTokens":120]]
        try (JSONSerialization.data(withJSONObject:record)+Data([10])).write(to:ledger)
        let now=Date(timeIntervalSince1970:Double(stamp));var reader=OpenCodexIncrementalLedger()
        let compact=try reader.snapshot(url:ledger,catalogURL:nil,now:now)
        let regular=QuotaDashboardSnapshot.build(.openCodex(try reader.load(url:ledger,catalogURL:nil)),now:now)
        let key=try XCTUnwrap(AntigravityTokenUsage.responseKey(model:"gemini-3.8-flash",responseID:"response-one"))
        XCTAssertTrue(compact.providerResponseKeys.contains(key));XCTAssertTrue(regular.providerResponseKeys.contains(key))
    }
    func testIncompleteLedgerRecordNeverDisplacesValidNativeUsage() throws {
        for flags in ["\"streamAborted\":true,\"usageStatus\":\"reported\"", "\"usageStatus\":\"unsupported\""] {
            let row="{\"requestId\":\"one\",\"upstreamResponseId\":\"same\",\"timestamp\":\"2026-08-27T12:00:00Z\",\"provider\":\"antigravity-pool\",\"resolvedModel\":\"gemini-3.8-flash\",\(flags),\"usage\":{\"inputTokens\":100,\"outputTokens\":20}}"
            let data=AILSA_SSLedgerMeteringReader(pricingCatalog:.empty).read(data:Data(row.utf8))
            let record=try XCTUnwrap(data.records.first)
            XCTAssertTrue(QuotaDashboardSnapshot.contribution(record).providerResponseKeys.isEmpty)
        }
    }
    func testJSONLFallbackAndNativeDatabasePrecedence() throws {
        let r=try root(), native=try root()
        let json="{\"type\":\"usage\",\"sessionId\":\"cache\",\"modelId\":\"gemini-3.8-flash\",\"input\":100,\"output\":30,\"cacheRead\":50,\"timestamp\":1787832000250}\n"
        try json.write(to:r.appendingPathComponent("cache.jsonl"),atomically:true,encoding:.utf8)
        var reader=AntigravityTokenUsageReader()
        let fallback=try reader.read(roots:[native],cacheRoot:r)
        XCTAssertEqual(fallback.entries.first?.contribution.value.tokens.total,180)
        try db(native,blobs:[F.blob()])
        let primary=try reader.read(roots:[native],cacheRoot:r)
        XCTAssertEqual(primary.entries.count,1);XCTAssertEqual(primary.entries.first?.contribution.value.tokens.total,187)
    }

    func testLargeToolEnvelopeDoesNotHideOtherGenerationMetadata() throws {
        let r=try root()
        let large=F.message(3,[UInt8](repeating:0x61,count:17*1024*1024))+F.blobWithRootEnvelope(botID:"large",model:"gemini-3.8-flash")
        try db(r,blobs:[large,F.blobWithRootEnvelope(botID:"small",model:"gemini-3.8-flash")],steps:[F.stepMetadataBlob(botID:"large"),F.stepMetadataBlob(botID:"small")])
        let native=try read(r);XCTAssertEqual(native.entries.count,2);XCTAssertEqual(native.entries.reduce(0){$0+$1.contribution.value.tokens.total},374)
        XCTAssertFalse(native.diagnostics.partial)
        var small=AntigravityTokenScanner.Limits();small.blobBytes=1024*1024
        let capped=try read(r,limits:small);XCTAssertTrue(capped.diagnostics.partial)
    }
    func testZeroCounterMetadataDoesNotInventConsumedRequestsOrUnknownModelRows() throws {
        let r=try root();try db(r,blobs:[F.blob(model:nil,label:nil,input:0,output:0,cacheRead:0,reasoning:0)])
        let native=try read(r);XCTAssertTrue(native.entries.isEmpty);XCTAssertEqual(native.diagnostics.emptyRecords,1)
        XCTAssertEqual(native.diagnostics.requests,0);XCTAssertFalse(native.diagnostics.partial)
    }

}

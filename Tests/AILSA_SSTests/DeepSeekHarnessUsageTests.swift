import Foundation
import XCTest
@testable import AILSA_SS

final class DeepSeekHarnessUsageTests: XCTestCase {
    private func row(model: String="deepseek-flash", provider: String="deepseek-official", seq: Int=1, step: Int=1, response: String?="response-1", total: Int=75, time: String="2026-10-30T02:00:00Z") -> [String:Any] {
        var r:[String:Any]=["session":"fixture-session","turn":1,"step":step,"epoch":0,"seq":seq,
            "time":Int64(ISO8601DateFormatter().date(from:time)!.timeIntervalSince1970*1000),
            "provider":provider,"model":model,"requestedOnly":false,
            "usage":["inputTokens":10,"outputTokens":20,"cacheReadTokens":40,"cacheWriteTokens":5,"totalTokens":total]]
        if let response {r["responseID"]=response};return r
    }
    private func data(_ records:[[String:Any]]) throws -> Data {
        try JSONSerialization.data(withJSONObject:["version":1,"files":1,"partial":false,"records":records])
    }
    func testDisjointNativeCacheBucketsNormalizeOnceAndUsePeakUSD() throws {
        let result=try DeepSeekHarnessUsageReader.decode(data([row()]))
        let value=try XCTUnwrap(result.entries.first).contribution.value
        XCTAssertEqual(value.tokens.input,55);XCTAssertEqual(value.tokens.cachedInput,40)
        XCTAssertEqual(value.tokens.cacheWriteInput,5);XCTAssertEqual(value.tokens.output,20)
        XCTAssertEqual(value.tokens.total,75);XCTAssertEqual(value.reference.pico,28_740_000)
        XCTAssertEqual(value.reported,1);XCTAssertEqual(value.confirmed.count,0)
    }
    func testNativeFlashAndProUsePerRequestOffPeakWeekendAndHolidayPrices() throws {
        for (model,peak) in [("deepseek-flash",Int64(28_740_000)),("deepseek-v4-pro",Int64(100_760_000))] {
            XCTAssertEqual(try DeepSeekHarnessUsageReader.decode(data([row(model:model)])).entries.first?.contribution.value.reference.pico,peak)
            for date in ["2026-10-30T12:00:00Z","2026-10-31T02:00:00Z","2026-10-01T02:00:00Z"] {
                XCTAssertEqual(try DeepSeekHarnessUsageReader.decode(data([row(model:model,time:date)])).entries.first?.contribution.value.reference.pico,peak/2)
            }
        }
    }
    func testInvalidTotalsAndNegativeCountersDoNotInventConsumption() throws {
        let bad=try DeepSeekHarnessUsageReader.decode(data([row(total:999)]))
        XCTAssertTrue(bad.entries.isEmpty);XCTAssertEqual(bad.diagnostics.invalid,1)
        var negative=row();negative["usage"]=["inputTokens":-1,"outputTokens":1]
        XCTAssertTrue(try DeepSeekHarnessUsageReader.decode(data([negative])).entries.isEmpty)
    }
    func testNewestDurableSettlementReplacesRatherThanAddsItsEarlierSample() throws {
        let result=try DeepSeekHarnessUsageReader.decode(data([row(seq:2),row(seq:1),row(seq:2)]))
        XCTAssertEqual(result.entries.count,1);XCTAssertEqual(result.diagnostics.duplicates,2)
        XCTAssertEqual(result.entries.first?.contribution.value.tokens.total,75)
    }
    func testConflictingCopiesWithTheSameSequenceRemainUnavailable() throws {
        var changed=row();changed["requestedOnly"]=true
        let result=try DeepSeekHarnessUsageReader.decode(data([row(),changed]))
        XCTAssertTrue(result.entries.isEmpty);XCTAssertEqual(result.diagnostics.invalid,1)
    }
    func testNativeAndLedgerDeepSeekRoutesHaveOneDisplayFamily() {
        XCTAssertEqual(QuotaModelKey(provider:"deepseek",model:"deepseek-flash").familyKey,
                       QuotaModelKey(provider:"dsh-account",model:"deepseek-flash").familyKey)
        XCTAssertNotEqual(QuotaModelKey(provider:"deepseek",model:"deepseek-v4-pro").familyKey,
                          QuotaModelKey(provider:"deepseek",model:"deepseek-flash").familyKey)
    }
    func testSeparateRetryEpochsAndStepsRemainSeparateRequests() throws {
        var retry=row(seq:2,response:"response-2");retry["epoch"]=1
        let result=try DeepSeekHarnessUsageReader.decode(data([row(),retry,row(seq:3,step:2,response:"response-3")]))
        XCTAssertEqual(result.entries.count,3)
    }
    func testPublicReaderIgnoresUnknownCustomProvidersAndModels() throws {
        let result=try DeepSeekHarnessUsageReader.decode(data([row(provider:"custom-local"),row(model:"unreleased",step:2,response:"different")]))
        XCTAssertTrue(result.entries.isEmpty);XCTAssertEqual(result.diagnostics.unsupported,2)
    }
    func testLedgerOverlapUsesResponseIdentityRatherThanSimilarTokenCounts() throws {
        let now=ISO8601DateFormatter().date(from:"2026-10-30T02:30:00Z")!
        let result=try DeepSeekHarnessUsageReader.decode(data([row(),row(step:2,response:"different-response")]))
        var base=QuotaDashboardSnapshot.build(.openCodex(AILSA_SSLedgerMeteringReader(pricingCatalog:.empty).read(data:Data())),now:now)
        base.providerResponseKeys.insert(AntigravityTokenUsage.responseKey(model:"deepseek-flash",responseID:"response-1")!)
        let merged=result.merging(into:base,now:now,historyDays:30)
        XCTAssertEqual(merged.all.tokens.total,75);XCTAssertEqual(merged.deepSeekHarnessUsage?.overlaps,1)
        XCTAssertEqual(merged.days.values.reduce(0){$0+$1.total.tokens.total},75)
        XCTAssertEqual(merged.minuteBuckets.values.reduce(0){$0+$1.total.tokens.total},75)
    }
    func testDuplicateResponseAcrossDifferentSessionsIsNotAddedTwice() throws {
        var copied=row(step:2);copied["session"]="other-session"
        let result=try DeepSeekHarnessUsageReader.decode(data([row(),copied]))
        let now=ISO8601DateFormatter().date(from:"2026-10-30T02:30:00Z")!
        let base=QuotaDashboardSnapshot.build(.openCodex(AILSA_SSLedgerMeteringReader(pricingCatalog:.empty).read(data:Data())),now:now)
        let merged=result.merging(into:base,now:now,historyDays:30)
        XCTAssertEqual(merged.all.tokens.total,75);XCTAssertEqual(merged.deepSeekHarnessUsage?.overlaps,1)
    }
    func testCopiedNativeMessagesWithoutVendorResponseIDAreNotCountedTwice() throws {
        var first=row(response:nil),copy=row(step:2,response:nil)
        first["messageID"]="native-message";copy["messageID"]="native-message";copy["session"]="copied-session"
        let result=try DeepSeekHarnessUsageReader.decode(data([first,copy]))
        let now=ISO8601DateFormatter().date(from:"2026-10-30T02:30:00Z")!
        let base=QuotaDashboardSnapshot.build(.openCodex(AILSA_SSLedgerMeteringReader(pricingCatalog:.empty).read(data:Data())),now:now)
        XCTAssertEqual(result.merging(into:base,now:now,historyDays:30).all.tokens.total,75)
        copy["messageID"]="another-native-message"
        let distinct=try DeepSeekHarnessUsageReader.decode(data([first,copy]))
        XCTAssertEqual(distinct.merging(into:base,now:now,historyDays:30).all.tokens.total,150)
    }
    func testMissingFolderDoesNotLaunchRuntime() throws {
        var reader=DeepSeekHarnessUsageReader()
        let result=try reader.read(root:nil,runtime:nil,helper:nil)
        XCTAssertTrue(result.entries.isEmpty)
    }
    func testUnchangedSessionCacheAndAppendedDataInvalidation() throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer {try? FileManager.default.removeItem(at:root)}
        let file=root.appendingPathComponent("session.v4.jsonl");try Data("first".utf8).write(to:file)
        let fixture=try data([row()]);var reader=DeepSeekHarnessUsageReader()
        let dummy=URL(fileURLWithPath:"/unused")
        XCTAssertEqual(try reader.read(root:root,runtime:dummy,helper:dummy,load:{_,_,_ in fixture}).entries.count,1)
        XCTAssertEqual(try reader.read(root:root,runtime:nil,helper:nil).entries.count,1)
        try Data("appended".utf8).write(to:file)
        XCTAssertThrowsError(try reader.read(root:root,runtime:nil,helper:nil))
    }
}

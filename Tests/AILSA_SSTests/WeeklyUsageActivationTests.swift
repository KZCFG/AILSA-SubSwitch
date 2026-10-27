import Foundation
import XCTest
@testable import AILSA_SS

final class WeeklyUsageActivationTests:XCTestCase {
    func testProviderEvidenceAndResetExpireIndependentlyOfFirstRequestCountdown() {
        let now:Int64=2_000_000_000
        var usage=UsageSnapshot(fetchedAt:now,planType:nil,fiveHour:nil,oneWeek:.init(usedPercent:0,windowSeconds:604800,resetAt:now+3000),credits:nil)
        XCTAssertEqual(WeeklyUsageActivationState.resolve(usage:usage,receipt:nil,now:now),.idle)
        usage.oneWeek?.usedPercent=0.00001
        XCTAssertEqual(WeeklyUsageActivationState.resolve(usage:usage,receipt:nil,now:now),.active)
        XCTAssertEqual(WeeklyUsageActivationState.resolve(usage:usage,receipt:nil,now:now+301),.unknown)
        usage.oneWeek?.usedPercent=0
        let receipt=WeeklyUsageActivationRecord(attemptedAt:now,resetAt:now+3000,result:.init(model:"fixture",inputTokens:2,outputTokens:1,confirmedAt:now))
        XCTAssertEqual(WeeklyUsageActivationState.resolve(usage:usage,receipt:receipt,now:now+301),.active)
        usage.oneWeek?.resetAt=now+604800
        XCTAssertEqual(WeeklyUsageActivationState.resolve(usage:usage,receipt:receipt,now:now),.idle)
        usage.sourceAccountMatched=false
        XCTAssertEqual(WeeklyUsageActivationState.resolve(usage:usage,receipt:receipt,now:now),.unknown)
    }
    func testDurableClaimPreventsSecondGenerationAcrossServiceInstances() throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:dir)}
        let file=dir.appendingPathComponent("receipts.json"),first=WeeklyUsageActivationStore(path:file),second=WeeklyUsageActivationStore(path:file)
        try first.claim("fixture",resetAt:10000,now:1000)
        XCTAssertThrowsError(try second.claim("fixture",resetAt:10000,now:1001))
        XCTAssertNil(second.read("fixture")?.result)
        try first.confirm("fixture",result:.init(model:"m",inputTokens:2,outputTokens:1,confirmedAt:1002))
        XCTAssertEqual(second.read("fixture")?.result?.model,"m")
        let data=try String(contentsOf:file,encoding:.utf8)
        XCTAssertFalse(data.contains("Bearer"));XCTAssertFalse(data.contains("access_token"))
    }
    func testCodexUsesExactAccountAndOneCompletedGenerationOnly() async throws {
        let fixture=WeeklyRequestFixture()
        let client=WeeklyUsageRequestClient(loader:{ request in try await fixture.load(request) })
        let result=try await client.codex(accessToken:"fixture-token",accountID:"fixture-account")
        XCTAssertEqual(result.model,"gpt-6.1-terra");XCTAssertEqual(result.inputTokens,4);XCTAssertEqual(result.outputTokens,1)
        let requests=await fixture.requests
        XCTAssertEqual(requests.count,2)
        XCTAssertEqual(requests.last?.httpMethod,"POST")
        XCTAssertTrue(requests.allSatisfy{$0.url?.host=="chatgpt.com" && $0.value(forHTTPHeaderField:"ChatGPT-Account-Id")=="fixture-account"})
        let body=try JSONSerialization.jsonObject(with:XCTUnwrap(requests.last?.httpBody)) as! [String:Any]
        XCTAssertEqual(body["store"] as? Bool,false);XCTAssertEqual((body["tools"] as? [Any])?.count,0)
    }
    func testFailedCodexGenerationNeverRetriesOrReportsActivation() async {
        let fixture=WeeklyRequestFixture(fail:true)
        do{_ = try await WeeklyUsageRequestClient(loader:{request in try await fixture.load(request)}).codex(accessToken:"fixture-token",accountID:"a");XCTFail("Expected failure")}catch{}
        let count=await fixture.requests.count;XCTAssertEqual(count,2)
    }
}
private actor WeeklyRequestFixture {
    var requests:[URLRequest]=[]
    let fail:Bool
    init(fail:Bool=false){self.fail=fail}
    func load(_ request:URLRequest) throws -> (Data,URLResponse) {
        requests.append(request)
        let isModels=request.httpMethod != "POST"
        let text=isModels ? "{\"models\":[{\"slug\":\"gpt-6.1-sol\"},{\"slug\":\"gpt-6.1-terra\"}]}" : "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"model\":\"gpt-6.1-terra\",\"usage\":{\"input_tokens\":4,\"output_tokens\":1}}}\n\n"
        return (Data(text.utf8),HTTPURLResponse(url:request.url!,statusCode:!isModels && fail ? 429 : 200,httpVersion:nil,headerFields:[:])!)
    }
}

final class PoolClaudeAndTerraPricingTests:XCTestCase {
    private func record(_ model:String,provider:String="antigravity-pool",input:Int=100000,cache:Int=40000,tier:String?=nil) throws -> OpenCodexLedgerMeteringRecord {
        var row:[String:Any]=["requestId":"fixture","timestamp":"2026-10-27T08:00:00Z","provider":provider,"resolvedModel":model,"usageStatus":"reported","usage":["inputTokens":input,"outputTokens":20000,"cachedInputTokens":cache,"reasoningOutputTokens":4000]]
        if let tier{row["tierOutcome"]=["confirmation":"vendor","canonical":tier]}
        return try XCTUnwrap(AILSA_SSLedgerMeteringReader(pricingCatalog:.empty).read(data:JSONSerialization.data(withJSONObject:row)).records.first)
    }
    func testPoolClaudeThinkingIsPricedAndReasoningIsNotCountedTwice() throws {
        let opus=try record("claude-opus-4-6-thinking")
        XCTAssertEqual(opus.standardReferenceEstimate.picoUSD,820_000_000_000)
        XCTAssertEqual(try record("claude-sonnet-4-6").standardReferenceEstimate.picoUSD,492_000_000_000)
        XCTAssertEqual(QuotaModelKey(provider:"antigravity-pool",model:"claude-opus-4-6-thinking").familyKey.model,"Claude Opus 4.6")
        XCTAssertNil(try record("claude-opus-4-6-fiction").standardReferenceEstimate.picoUSD)
        XCTAssertNil(try record("claude-opus-4-6",provider:"unverified-proxy").standardReferenceEstimate.picoUSD)
        XCTAssertNil(opus.pricing.picoUSD)
    }
    func testTerraOfficialCacheLongContextAndConfirmedFastRates() throws {
        XCTAssertEqual(try record("gpt-6.1-terra",provider:"openai").standardReferenceEstimate.picoUSD,162_000_000_000)
        XCTAssertEqual(try record("gpt-6.1-terra",provider:"openai",input:272000,cache:0).standardReferenceEstimate.picoUSD,372_000_000_000)
        XCTAssertEqual(try record("gpt-6.1-terra",provider:"openai",input:272001,cache:0).standardReferenceEstimate.picoUSD,694_002_000_000)
        XCTAssertEqual(try record("gpt-6.1-terra",provider:"openai",tier:"fast").standardReferenceEstimate.picoUSD,324_000_000_000)
        XCTAssertEqual(QuotaModelKey(provider:"openai",model:"gpt-6.1-terra").familyKey.model,"GPT-6.1 Terra")
    }
}

import Foundation
import XCTest
@testable import AILSA_SS

final class PricingCoverageTests:XCTestCase {
    private func record(_ model:String,provider:String="google-antigravity",input:Int=207,output:Int=9,cache:Int=128,reasoning:Int=0,total:Int?=nil,tier:String?=nil) throws -> OpenCodexLedgerMeteringRecord {
        var usage:[String:Any]=["inputTokens":input,"outputTokens":output,"cachedInputTokens":cache,"reasoningOutputTokens":reasoning]
        if let total{usage["totalTokens"]=total}
        var row:[String:Any]=["requestId":"fixture","timestamp":"2026-10-27T04:00:00Z","provider":provider,"resolvedModel":model,"usageStatus":"reported","usage":usage]
        if let tier{row["tierOutcome"]=["confirmation":"vendor","canonical":tier]}
        return try XCTUnwrap(AILSA_SSLedgerMeteringReader(pricingCatalog:.empty).read(data:JSONSerialization.data(withJSONObject:row)).records.first)
    }
    func testAllKnownAntigravityClaudeEffortVariantsUseTheirBaseOfficialPrice() throws {
        let options=["","-none","-low","-medium","-high","-xhigh","-max","-ultra","-thinking","-20261023-medium"]
        for provider in ["google-antigravity","antigravity-pool","anthropic","combo"] {
            for (base,expected) in [("claude-sonnet-5-5",260_800_000),("claude-opus-5-5",521_600_000)] {
                for option in options {
                    let value=try record(base+option,provider:provider)
                    XCTAssertEqual(value.standardReferenceEstimate.picoUSD,Int64(expected))
                    XCTAssertEqual(value.tokens.totalTokens,216)
                    XCTAssertNil(value.pricing.picoUSD)
                }
            }
        }
        XCTAssertNil(try record("claude-sonnet-5-5-medium-unreleased").standardReferenceEstimate.picoUSD)
        XCTAssertNil(try record("claude-opus-5-6-high").standardReferenceEstimate.picoUSD)
    }
    func testGrokReasoningMismatchHasExplicitUSDBoundWithoutChangingTokens() throws {
        let value=try record("grok-4.5",provider:"xai",reasoning:59)
        XCTAssertTrue(value.tokenSemanticIssue)
        XCTAssertEqual(value.tokenSemanticIssueReason,"reasoningOutsideOutput")
        XCTAssertEqual(value.tokens.inputTokens,207);XCTAssertEqual(value.tokens.outputTokens,9)
        XCTAssertEqual(value.tokens.reasoningOutputTokens,59);XCTAssertEqual(value.tokens.totalTokens,216)
        XCTAssertNil(value.pricing.picoUSD)
        let bound=try XCTUnwrap(OpenCodexStandardReferenceEstimator.maximumReference(for:value))
        XCTAssertEqual(bound.reason,"reasoning_output_upper_bound")
        XCTAssertEqual(bound.picoUSD,1_644_000_000)
        let contribution=QuotaDashboardSnapshot.contribution(value).value
        XCTAssertEqual(contribution.tokens.total,216);XCTAssertEqual(contribution.reference.pico,bound.picoUSD)
        XCTAssertEqual(contribution.highEstimateRecords,1)
        XCTAssertEqual(contribution.states["reasoning_output_upper_bound"],1)
        let totalConflict=try record("grok-4.5",provider:"xai",reasoning:59,total:999)
        XCTAssertNil(OpenCodexStandardReferenceEstimator.maximumReference(for:totalConflict))
        XCTAssertNil(OpenCodexStandardReferenceEstimator.maximumReference(for:try record("grok-4.5",provider:"xai",cache:999,reasoning:59)))
    }
    func testComposerUsesOfficialEquivalentAndKeepsItsRawRoute() throws {
        let ordinary=try record("grok-composer-2.5-fast",provider:"xai")
        XCTAssertEqual(ordinary.standardReferenceEstimate.picoUSD,436_000_000)
        XCTAssertEqual(ordinary.standardReferenceEstimate.priceBasis,"official_composer_equivalent_reference")
        XCTAssertEqual(ordinary.routeProvider,"xai");XCTAssertEqual(ordinary.resolvedModel,"grok-composer-2.5-fast")
        XCTAssertNil(ordinary.pricing.picoUSD)
        let mixed=try record("grok-composer-2.5-fast",provider:"xai",reasoning:83)
        XCTAssertEqual(OpenCodexStandardReferenceEstimator.maximumReference(for:mixed)?.picoUSD,2_001_000_000)
        XCTAssertEqual(QuotaDashboardSnapshot.contribution(mixed).value.states["official_model_equivalent_reference"],1)
        XCTAssertEqual(QuotaModelKey(provider:"xai",model:"grok-composer-2.5-fast").familyKey.model,"Composer 2.5 Fast")
    }
    func testConfirmedFastClaudeAndGrokPriorityUseOfficialMultipliers() throws {
        XCTAssertEqual(try record("claude-opus-5-5-high",tier:"fast").standardReferenceEstimate.picoUSD,1_043_200_000)
        XCTAssertEqual(try record("grok-4.5",provider:"xai",tier:"priority").standardReferenceEstimate.picoUSD,500_800_000)
    }
    func testNativeCacheWriteSubsetPricesWithTransparentClaudeUpperBound() {
        let tokens=OpenCodexUsageTokens(inputTokens:300,outputTokens:10,totalTokens:310,cachedInputTokens:100,cacheReadInputTokens:100,cacheCreationInputTokens:50,reasoningOutputTokens:0,totalSemantics:.inputPlusOutput)
        var input=OpenCodexStandardReferenceInput(provider:"google-antigravity",resolvedModel:"claude-sonnet-5-5-medium",requestedModel:nil,modelEcho:nil,usageStatus:.reported,usageEstimated:false,streamAborted:false,currency:"USD",apiEquivalentEligibility:nil,tierOutcomeConfirmation:nil,tierOutcomeCanonical:nil,responseServiceTier:nil,fastOutcome:nil,confirmedServiceTier:nil,fastGrantEvidence:.unknown,tokens:tokens,tokenSemanticIssue:false,occurredAt:Date(),cacheCreationIsInputSubset:true)
        let price=OpenCodexStandardReferenceEstimator().estimate(input)
        XCTAssertEqual(price.picoUSD,610_000_000)
        XCTAssertEqual(price.priceBasis,"official_cache_write_upper_bound");XCTAssertTrue(price.estimatePartial)
        input.cacheCreationIsInputSubset=false
        XCTAssertNil(OpenCodexStandardReferenceEstimator().estimate(input).picoUSD)
    }
}

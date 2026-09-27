import XCTest
@testable import AILSA_SS

/// Pricing bases must each keep their own verification date; the UI is not
/// allowed to collapse them into a single hard-coded "checked on" string.
final class QuotaPricingProvenanceTests: XCTestCase {
    func testAuditDateIsParsedFromCatalogVersion() {
        XCTAssertEqual(OpenCodexPricingCatalog.auditDate(fromCatalogVersion: "v1|audit=2026-09-15|generated=2026-09-16T00:00:00Z"), "2026-09-15")
        XCTAssertNil(OpenCodexPricingCatalog.auditDate(fromCatalogVersion: "v1|generated=2026-09-16T00:00:00Z"))
        XCTAssertNil(OpenCodexPricingCatalog.auditDate(fromCatalogVersion: "v1|audit="))
        XCTAssertNil(OpenCodexPricingCatalog.auditDate(fromCatalogVersion: nil))
    }

    func testStandardReferenceDoesNotClaimAnUnverifiedAudit() {
        XCTAssertNil(OpenCodexStandardReferenceEstimator.auditDate)
    }

    func testCompactSnapshotCarriesProvenanceUnchanged() {
        let provenance = [
            QuotaPricingProvenance(basis: .standardReference, auditDate: "2026-09-16"),
            QuotaPricingProvenance(basis: .verifiedCatalog, auditDate: "2026-09-15"),
        ]
        let snapshot = QuotaDashboardSnapshot.compact([String: QuotaContribution]().values, discarded: 0, now: Date(), pricingProvenance: provenance)
        XCTAssertEqual(snapshot.pricingProvenance, provenance)
    }

    func testProvenanceLineDistinguishesMissingDate() {
        let dated = QuotaPricingProvenanceText.line(QuotaPricingProvenance(basis: .verifiedCatalog, auditDate: "2026-09-15"))
        let undated = QuotaPricingProvenanceText.line(QuotaPricingProvenance(basis: .vendorReported, auditDate: nil))
        XCTAssertTrue(dated.contains("2026-09-15"))
        XCTAssertFalse(undated.contains("2026"))
    }
}

/// Small-panel layout rules: the menu bar panel can shrink to 520pt on small
/// displays; pages must adapt (denser layout) rather than clip or scroll.
final class PanelHeightLayoutRulesTests: XCTestCase {
    func testAccountsSwitchToCompactCardsBelowThreshold() {
        XCTAssertTrue(LayoutRules.accountsForcesCompactCards(panelHeight: LayoutRules.minimumPanelHeight))
        XCTAssertTrue(LayoutRules.accountsForcesCompactCards(panelHeight: 639))
        XCTAssertFalse(LayoutRules.accountsForcesCompactCards(panelHeight: 640))
        XCTAssertFalse(LayoutRules.accountsForcesCompactCards(panelHeight: LayoutRules.accountsPanelHeight))
        XCTAssertFalse(LayoutRules.accountsForcesCompactCards(panelHeight: nil), "standalone windows without a panel size keep the user's choice")
    }

    func testQuotaDashboardFitsMinimumPanelWithoutTrend() {
        // QuotaManagementPageView passes panel height minus 114pt of header/picker chrome.
        let available = Double(LayoutRules.minimumPanelHeight) - 114
        let layout = QuotaDashboardLayout(height: available, expandedIntraday: true)
        XCTAssertFalse(layout.showsTrend)
        XCTAssertGreaterThanOrEqual(layout.rows, 1)
        // range 42 + KPI 78 + table header 24 + rows*33 + paging 26 + trend button ~22 + footer 26 + 6 gaps*10
        let contentHeight = 42.0 + 78 + 24 + Double(layout.rows) * 33 + 26 + 22 + 26 + 60
        XCTAssertLessThanOrEqual(contentHeight, available)
    }

    func testQuotaDashboardFitsDesignPanelWithIntradayChart() {
        let available = Double(LayoutRules.quotaManagementPanelHeight) - 114
        let layout = QuotaDashboardLayout(height: available, expandedIntraday: true)
        XCTAssertTrue(layout.showsTrend)
        XCTAssertEqual(layout.trendHeight, 180)
        let contentHeight = 42.0 + 78 + 24 + Double(layout.rows) * 33 + 26 + 180 + 26 + 60
        XCTAssertLessThanOrEqual(contentHeight, available)
    }

    func testQuotaDashboardUsesTheSameLargeChartForDatedRanges() {
        let available = Double(LayoutRules.quotaManagementPanelHeight) - 114
        let today = QuotaDashboardLayout(height: available, provider: .codex, range: 1)
        for range in [7, 30] {
            let layout = QuotaDashboardLayout(height: available, provider: .codex, range: range)
            XCTAssertTrue(layout.showsTrend)
            XCTAssertEqual(layout.trendHeight, today.trendHeight)
            XCTAssertEqual(layout.trendHeight, 180)
            let contentHeight = 42.0 + 78 + 24 + Double(layout.rows) * 33 + 26 + 180 + 26 + 60
            XCTAssertLessThanOrEqual(contentHeight, available)
        }
    }

    func testCodexChartFixPreservesOtherProviderLayouts() {
        let available = Double(LayoutRules.quotaManagementPanelHeight) - 114
        for range in [7, 30] {
            XCTAssertEqual(QuotaDashboardLayout(height: available, provider: .cursor, range: range).trendHeight, 76)
            XCTAssertEqual(QuotaDashboardLayout(height: available, provider: .antigravity, range: range).trendHeight, 180)
        }
    }
}

final class KimiSeptemberPricingTests: XCTestCase {
    private func estimate(_ model: String) -> AILSA_SSStandardReferenceEstimate {
        OpenCodexStandardReferenceEstimator().estimate(OpenCodexStandardReferenceInput(
            provider: "kimi-code", resolvedModel: model, requestedModel: nil, modelEcho: nil,
            usageStatus: .reported, usageEstimated: false, streamAborted: false,
            currency: "USD", apiEquivalentEligibility: nil, tierOutcomeConfirmation: nil,
            tierOutcomeCanonical: nil, responseServiceTier: nil, fastOutcome: nil,
            confirmedServiceTier: nil, fastGrantEvidence: .unknown,
            tokens: OpenCodexUsageTokens(inputTokens: 1_000_000, outputTokens: 1_000_000,
                totalTokens: 2_000_000, cachedInputTokens: 200_000, cacheReadInputTokens: 200_000,
                cacheCreationInputTokens: 0, reasoningOutputTokens: nil, totalSemantics: .inputPlusOutput),
            tokenSemanticIssue: false))
    }
    func testK3ContextVariantsHaveSameReferencePrice() {
        XCTAssertEqual(estimate("k3-256k").picoUSD, estimate("k3").picoUSD)
        XCTAssertEqual(estimate("k3[1m]").picoUSD, estimate("k3").picoUSD)
        XCTAssertEqual(estimate("k3").picoUSD, 17_460_000_000_000)
    }
    func testHighSpeedHasItsOwnPublishedRate() {
        XCTAssertEqual(estimate("kimi-for-coding-highspeed").picoUSD, 9_596_000_000_000)
        XCTAssertEqual(estimate("kimi-k2.7-code").picoUSD, 4_798_000_000_000)
    }
    func testPreviewUsesExplicitUserMappedOldModelPrice() {
        XCTAssertEqual(estimate("kimi-for-coding").picoUSD, 4_798_000_000_000)
        XCTAssertEqual(estimate("kimi-for-coding").priceBasis, "user_mapped_official_standard_reference")
        XCTAssertEqual(QuotaModelKey(provider: "kimi-code", model: "kimi-for-coding").familyKey.model, "Kimi K2.8 Preview")
    }
}

final class Grok47PricingTests: XCTestCase {
    private func estimate(_ model: String = "grok-4.7", input: Int = 100_000,
                          tier: String? = nil, fast: OpenCodexFastGrantEvidence = .unknown) -> AILSA_SSStandardReferenceEstimate {
        OpenCodexStandardReferenceEstimator().estimate(OpenCodexStandardReferenceInput(
            provider: "xai", resolvedModel: model, requestedModel: nil, modelEcho: nil,
            usageStatus: .reported, usageEstimated: false, streamAborted: false,
            currency: "USD", apiEquivalentEligibility: nil, tierOutcomeConfirmation: nil,
            tierOutcomeCanonical: nil, responseServiceTier: tier, fastOutcome: nil,
            confirmedServiceTier: tier, fastGrantEvidence: fast,
            tokens: OpenCodexUsageTokens(inputTokens: input, outputTokens: 10_000,
                totalTokens: input + 10_000, cachedInputTokens: 20_000, cacheReadInputTokens: 20_000,
                cacheCreationInputTokens: 0, reasoningOutputTokens: nil, totalSemantics: .inputPlusOutput),
            tokenSemanticIssue: false))
    }

    func testPublishedRatesMatchGrok46AndApplyCacheDiscount() {
        XCTAssertEqual(estimate().picoUSD, 230_000_000_000)
        XCTAssertEqual(estimate().picoUSD, estimate("grok-4.6").picoUSD)
    }

    func testLongContextBoundaryIncludesExactly200k() {
        XCTAssertEqual(estimate(input: 199_999).picoUSD, 429_998_000_000)
        XCTAssertEqual(estimate(input: 200_000).picoUSD, 860_000_000_000)
    }

    func testBuildIdentityUsesReferencePriceAndGroupsWithGrok47() {
        let build = estimate("grok-4.7-build")
        XCTAssertEqual(build.picoUSD, estimate().picoUSD)
        XCTAssertEqual(build.priceBasis, "user_mapped_official_standard_reference")
        XCTAssertEqual(QuotaModelKey(provider: "xai", model: "grok-4.7-build").familyKey.model, "Grok 4.7")
        XCTAssertEqual(QuotaModelKey(provider: "cursor-proxy", model: "grok-4.7").familyKey.model, "Grok 4.7")
    }

    func testPriorityRequiresConfirmedGrantAndUsesDoubleRates() {
        XCTAssertEqual(estimate(tier: "priority", fast: .explicitlyGranted).picoUSD, 460_000_000_000)
        XCTAssertEqual(estimate("grok-4.7-build", input: 200_000, tier: "priority", fast: .explicitlyGranted).picoUSD, 1_720_000_000_000)
        XCTAssertEqual(estimate(tier: "priority", fast: .unknown).picoUSD, estimate().picoUSD)
        XCTAssertNil(estimate(fast: .explicitlyGranted).picoUSD)
    }

    func testBuildFastUsesGrok47ReferenceWithoutInferringPriority() {
        let fast = estimate("grok-4.7-build-fast", tier: "priority")
        XCTAssertEqual(fast.picoUSD, 230_000_000_000)
        XCTAssertEqual(fast.priceBasis, "user_mapped_official_standard_reference")
        XCTAssertEqual(fast.leaf, "grok-4.7")
        XCTAssertNil(fast.fastGranted)
        XCTAssertEqual(QuotaModelKey(provider: "xai", model: "grok-4.7-build-fast").familyKey,
                       QuotaModelKey(provider: "xai", model: "grok-4.7").familyKey)
    }

    func testBuildFastKeepsLongContextBoundaryAndConfirmedPriorityRates() {
        XCTAssertEqual(estimate("grok-4.7-build-fast", input: 199_999).picoUSD, 429_998_000_000)
        XCTAssertEqual(estimate("grok-4.7-build-fast", input: 200_000).picoUSD, 860_000_000_000)
        XCTAssertEqual(estimate("grok-4.7-build-fast", input: 200_000, tier: "priority", fast: .explicitlyGranted).picoUSD, 1_720_000_000_000)
    }

    func testBuildFastLedgerBackfillPreservesTokensDeduplicationAndOtherModels() throws {
        let fast = #"{"requestId":"fast","timestamp":"2026-09-27T10:00:00Z","provider":"xai","resolvedModel":"grok-4.7-build-fast","requestedModel":"xai/grok-4.7-build-fast","configuredServiceTier":"default","apiEquivalentEligibility":"not_eligible_unknown_identity","tierOutcome":{"confirmation":"unknown","fastOutcome":"unknown"},"usageStatus":"reported","usage":{"inputTokens":100000,"outputTokens":10000,"cachedInputTokens":20000,"totalTokens":110000}}"#
        let other = fast.replacingOccurrences(of: #""requestId":"fast""#, with: #""requestId":"other""#)
            .replacingOccurrences(of: "grok-4.7-build-fast", with: "grok-4.6")
            .replacingOccurrences(of: #""apiEquivalentEligibility":"not_eligible_unknown_identity","#, with: "")
        let missing = #"{"requestId":"missing","timestamp":"2026-09-27T11:00:00Z","provider":"xai","requestedModel":"xai/grok-4.7-build-fast","usageStatus":"unreported"}"#
        let reader = AILSA_SSLedgerMeteringReader(pricingCatalog: .empty)
        let analytics = reader.read(data: Data([fast, fast, other, missing].joined(separator: "\n").utf8))
        XCTAssertEqual(analytics.records.count, 3)
        XCTAssertEqual(analytics.coverage.ledgerDuplicateRowsDiscarded, 1)
        let fastRecord = try XCTUnwrap(analytics.records.first { $0.requestID == "fast" })
        XCTAssertEqual(fastRecord.standardReferenceEstimate.picoUSD, 230_000_000_000)
        XCTAssertNil(fastRecord.pricing.picoUSD)
        let otherRecord = try XCTUnwrap(analytics.records.first { $0.requestID == "other" })
        let otherAlone = try XCTUnwrap(reader.read(data: Data(other.utf8)).records.first)
        XCTAssertEqual(otherRecord, otherAlone)
        let now = ISO8601DateFormatter().date(from: "2026-09-27T12:00:00Z")!
        let snapshot = QuotaDashboardSnapshot.build(.openCodex(analytics), now: now)
        XCTAssertEqual(snapshot.all.tokens.total, 220_000)
        XCTAssertEqual(snapshot.all.reference.pico, 460_000_000_000)
        XCTAssertEqual(snapshot.all.reference.count, 2)
        XCTAssertEqual(snapshot.all.reported, 2)
    }

    func testBuildFastNameCannotRepairMissingResolvedIdentity() throws {
        let row = #"{"requestId":"unresolved","timestamp":"2026-09-27T10:00:00Z","provider":"xai","model":"grok-4.7-build-fast","requestedModel":"xai/grok-4.7-build-fast","usageStatus":"reported","usage":{"inputTokens":100000,"outputTokens":10000,"totalTokens":110000}}"#
        let record = try XCTUnwrap(AILSA_SSLedgerMeteringReader(pricingCatalog: .empty).read(data: Data(row.utf8)).records.first)
        XCTAssertEqual(record.standardReferenceEstimate.status, .unknownIdentity)
        XCTAssertNil(record.standardReferenceEstimate.picoUSD)
    }

    func testBuildFastConflictingReasoningRetainsTokensButDoesNotInventPrice() throws {
        let row = #"{"requestId":"conflicting","timestamp":"2026-09-27T10:00:00Z","provider":"xai","resolvedModel":"grok-4.7-build-fast","usageStatus":"reported","usage":{"inputTokens":100000,"outputTokens":100,"cachedInputTokens":20000,"reasoningOutputTokens":200}}"#
        let record = try XCTUnwrap(AILSA_SSLedgerMeteringReader(pricingCatalog: .empty).read(data: Data(row.utf8)).records.first)
        XCTAssertEqual(record.standardReferenceEstimate.status, .usageSemanticsConflict)
        XCTAssertNil(record.standardReferenceEstimate.picoUSD)
        let contribution = QuotaDashboardSnapshot.contribution(record)
        XCTAssertEqual(contribution.value.tokens.total, 100_100)
        XCTAssertEqual(contribution.value.reported, 1)
        XCTAssertEqual(contribution.value.reference.count, 0)
    }

    func testNewCatalogEntryDoesNotInvalidateOldAuditDates() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = repo.appendingPathComponent("Sources/AILSA_SS/Resources/AILSA_SS-runtime-pricing-bindings-v1.json")
        let catalog = try AILSA_SSVerifiedPricingCatalogLoader.load(url: url)
        let newBindings = catalog.bindings.filter { $0.provider == "xai" && $0.resolvedModel == "grok-4.7" }
        XCTAssertEqual(newBindings.count, 6)
        XCTAssertTrue(newBindings.contains { $0.serviceTier == "priority" && $0.inputPicoUSDPerToken == 8_000_000 })
        XCTAssertTrue(catalog.bindings.contains { $0.provider == "xai" && $0.resolvedModel == "grok-4.6" })
        XCTAssertFalse(catalog.bindings.contains { $0.resolvedModel == "grok-4.7-build" })
        XCTAssertFalse(catalog.bindings.contains { $0.resolvedModel == "grok-4.7-build-fast" })
    }
}

final class GPT6SolLunaPricingTests: XCTestCase {
    private func estimate(_ model: String, input: Int = 100_000, provider: String = "openai") -> AILSA_SSStandardReferenceEstimate {
        OpenCodexStandardReferenceEstimator().estimate(OpenCodexStandardReferenceInput(
            provider: provider, resolvedModel: model, requestedModel: nil, modelEcho: nil,
            usageStatus: .reported, usageEstimated: false, streamAborted: false,
            currency: "USD", apiEquivalentEligibility: nil, tierOutcomeConfirmation: nil,
            tierOutcomeCanonical: nil, responseServiceTier: nil, fastOutcome: nil,
            confirmedServiceTier: nil, fastGrantEvidence: .unknown,
            tokens: OpenCodexUsageTokens(inputTokens: input, outputTokens: 10_000,
                totalTokens: input + 10_000, cachedInputTokens: 20_000, cacheReadInputTokens: 20_000,
                cacheCreationInputTokens: 0, reasoningOutputTokens: 1_000, totalSemantics: .inputPlusOutput),
            tokenSemanticIssue: false))
    }
    func testOfficialStandardPricesAndCachedInput() {
        XCTAssertEqual(estimate("gpt-6-sol").picoUSD, 264_000_000_000)
        XCTAssertEqual(estimate("gpt-6-luna").picoUSD, 13_200_000_000)
        XCTAssertEqual(estimate("gpt-6-sol").priceBasis, OpenCodexStandardReferenceEstimator.priceBasis)
        XCTAssertNil(estimate("gpt-6-sol", provider: "unknown-proxy").picoUSD)
    }
    func testLongContextStartsStrictlyAbove272kAndPricesWholeRequest() {
        XCTAssertEqual(estimate("gpt-6-sol", input: 272_000).picoUSD, 608_000_000_000)
        XCTAssertEqual(estimate("gpt-6-sol", input: 272_001).picoUSD, 1_166_004_000_000)
        XCTAssertEqual(estimate("gpt-6-luna", input: 272_000).picoUSD, 30_400_000_000)
        XCTAssertEqual(estimate("gpt-6-luna", input: 272_001).picoUSD, 58_300_200_000)
    }
    func testNewCatalogModelsHaveSeparateAuditAndConfirmedFastPrices() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalog = try AILSA_SSVerifiedPricingCatalogLoader.load(url: repo.appendingPathComponent("Sources/AILSA_SS/Resources/AILSA_SS-runtime-pricing-bindings-v1.json"))
        for (model, input) in [("gpt-6-sol", Int64(8_000_000)), ("gpt-6-luna", Int64(400_000))] {
            let bindings = catalog.bindings.filter { $0.provider == "openai" && $0.resolvedModel == model }
            XCTAssertEqual(bindings.count, 6)
            XCTAssertTrue(bindings.contains { $0.serviceTier == "fast" && $0.inputPicoUSDPerToken == input })
        }
        XCTAssertEqual(catalog.provenance?.auditDate, "2026-09-15")
    }
}

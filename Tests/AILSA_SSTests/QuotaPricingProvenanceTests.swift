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
        let layout = QuotaDashboardLayout(height: available, expandedIntraday: false)
        XCTAssertTrue(layout.showsTrend)
        XCTAssertEqual(layout.trendHeight, 180)
        let contentHeight = 42.0 + 78 + 24 + Double(layout.rows) * 33 + 26 + 180 + 26 + 60
        XCTAssertLessThanOrEqual(contentHeight, available)
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

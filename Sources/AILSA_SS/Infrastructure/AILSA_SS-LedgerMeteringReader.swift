import Foundation
import CoreFoundation

// MARK: - Stable DTO types

/// The four producer states in `ailsa.opencodex.usage.v1`.  Do not add a
/// default case: a new producer state must be consciously handled instead of
/// being converted into reported usage.
enum OpenCodexUsageStatus: String, CaseIterable, Sendable {
    case reported
    case unreported
    case unsupported
    case estimated
}

enum OpenCodexTokenSource: String, Sendable {
    case upstreamReported = "upstream_reported"
    case upstreamEstimated = "upstream_estimated"
    case localEstimated = "local_estimated"
    case unavailable
}

enum OpenCodexRouteIdentityStatus: String, Sendable {
    case resolved
    case requestedOnly = "requested_only"
    case unknown
}

enum OpenCodexPricingStatus: String, Sendable {
    case priced
    case estimatedUsage = "estimated_usage"
    case usageUnavailable = "usage_unavailable"
    case priceUnknown = "price_unknown"
    case modelUnresolved = "model_unresolved"
    case unsupported
    case streamAborted = "stream_aborted"
    case usageSemanticsConflict = "usage_semantics_conflict"
}

enum OpenCodexPricingValueKind: String, Sendable {
    case exactDerived = "exact_derived"
    case estimated
    case unavailable
}

enum OpenCodexCacheInputHandling: String, Sendable {
    /// Cache is known to be embedded in input and the official catalog has no
    /// separately attributable discount.  Price the primary input once.
    case embeddedAtInputRate = "embedded_at_input_rate"
    /// `cachedInputTokens` is a verified subset of input and replaces that
    /// subset's input rate; it is never added onto input.
    case cachedSubsetDiscounted = "cached_subset_discounted"
}

enum OpenCodexPricingCatalogEntryStatus: String, Sendable {
    case verified
    case unknown
    case unsupported
}

/// Preserve the distinction between no Fast evidence and a vendor-confirmed
/// non-Fast result. A Boolean alone turns unknown into false, which is unsafe
/// for confirmed-tier pricing.
enum OpenCodexFastGrantEvidence: String, Sendable {
    case unknown
    case explicitlyGranted = "explicitly_granted"
    case explicitlyNotGranted = "explicitly_not_granted"

    /// `nil` is meaningful: the producer did not provide a reconciled,
    /// vendor-confirmed Fast outcome. Do not collapse it into `false`.
    var fastGranted: Bool? {
        switch self {
        case .unknown: nil
        case .explicitlyGranted: true
        case .explicitlyNotGranted: false
        }
    }
}

struct OpenCodexUsageTokens: Equatable, Sendable {
    let inputTokens: Int?
    let outputTokens: Int?
    let totalTokens: Int?
    let cachedInputTokens: Int?
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?
    let reasoningOutputTokens: Int?
    let totalSemantics: TotalSemantics

    enum TotalSemantics: String, Sendable {
        case inputPlusOutput = "input_plus_output"
        case unavailable
    }

    static let unavailable = OpenCodexUsageTokens(
        inputTokens: nil,
        outputTokens: nil,
        totalTokens: nil,
        cachedInputTokens: nil,
        cacheReadInputTokens: nil,
        cacheCreationInputTokens: nil,
        reasoningOutputTokens: nil,
        totalSemantics: .unavailable
    )

    var hasPrimaryTokens: Bool {
        inputTokens != nil && outputTokens != nil && totalTokens != nil
    }
}

struct OpenCodexAPIEquivalent: Equatable, Sendable {
    let status: OpenCodexPricingStatus
    let valueKind: OpenCodexPricingValueKind
    /// USD * 10^12.  Integer arithmetic avoids binary floating-point pricing
    /// drift; UI code may only round when it renders this value.
    let picoUSD: Int64?
    let catalogBindingID: String?
    let catalogVersion: String?
    let officialSourceURL: String?

    var apiEquivalentUSD: String? {
        guard let picoUSD else { return nil }
        let scale: Int64 = 1_000_000_000_000
        let whole = picoUSD / scale
        let fraction = picoUSD % scale
        return "\(whole).\(String(format: "%012lld", fraction))"
    }

    static func unavailable(_ status: OpenCodexPricingStatus) -> OpenCodexAPIEquivalent {
        OpenCodexAPIEquivalent(
            status: status,
            valueKind: .unavailable,
            picoUSD: nil,
            catalogBindingID: nil,
            catalogVersion: nil,
            officialSourceURL: nil
        )
    }
}

struct OpenCodexLedgerSource: Equatable, Sendable {
    let kind: String
    let aggregationMode: String
    let contractSchema: String?
    let contractVersion: String?

    static let canonicalLedger = OpenCodexLedgerSource(
        kind: "opencodex_ledger",
        aggregationMode: "ledger_primary",
        contractSchema: "ailsa.opencodex.usage.v1",
        contractVersion: "v1"
    )
}

struct OpenCodexLedgerMeteringRecord: Equatable, Identifiable, Sendable {
    /// This is the producer primary key, not a display label.  It is used to
    /// deduplicate a ledger turn; prompts and conversation payloads are never
    /// carried into this DTO.
    let requestID: String
    let occurredAt: Date
    let source: OpenCodexLedgerSource
    let requestedModel: String?
    let resolvedModel: String?
    /// Producer echo for disclosure only; never an identity fallback.
    let modelEcho: String?
    let displayModel: String?
    let routeProvider: String?
    let routeIdentityStatus: OpenCodexRouteIdentityStatus
    /// Inbound intent only.  It can be echoed by a bridge and is never a
    /// billing-tier proof.
    let requestedServiceTier: String?
    /// Non-nil only when the provider explicitly confirms its grant.
    let confirmedServiceTier: String?
    /// `nil` means the Fast outcome is unknown; it is never shorthand for a
    /// non-Fast grant. Prefer the explicit enum when branching on evidence.
    let fastGranted: Bool?
    let fastGrantEvidence: OpenCodexFastGrantEvidence
    let tierOutcomeConfirmation: String?
    let tierOutcomeCanonical: String?
    let responseServiceTier: String?
    let fastOutcome: String?
    let requestedEffort: String?
    let effectiveEffort: String?
    let usageStatus: OpenCodexUsageStatus
    let tokenSource: OpenCodexTokenSource
    let tokens: OpenCodexUsageTokens
    let pricing: OpenCodexAPIEquivalent
    /// Additive official-standard estimate. It never fills `pricing`.
    let standardReferenceEstimate: AILSA_SSStandardReferenceEstimate
    let streamAborted: Bool

    var id: String { requestID }
}

struct OpenCodexCoverageRatio: Equatable, Sendable {
    enum Unit: String, Sendable {
        case records
        case tokens
    }

    let numerator: Int
    let denominator: Int
    let unit: Unit
    let definition: String

    var percentage: Double? {
        guard denominator > 0 else { return nil }
        return Double(numerator) / Double(denominator)
    }
}

struct OpenCodexLedgerCoverage: Equatable, Sendable {
    let tokenMeteringRecordCoverage: OpenCodexCoverageRatio
    let pricingRecordCoverage: OpenCodexCoverageRatio
    let pricingTokenVolumeCoverage: OpenCodexCoverageRatio
    /// When true, the associated token-volume percentage is unavailable rather
    /// than a wrapped or partial value.
    let pricingTokenVolumeOverflowed: Bool
    let standardReferenceRecordCoverage: OpenCodexCoverageRatio
    let dedupeRequestIDCoverage: OpenCodexCoverageRatio
    let ledgerRowsSeen: Int
    let malformedLedgerRows: Int
    let ledgerRowsMissingRequestID: Int
    let ledgerRowsMissingTimestamp: Int
    let ledgerDuplicateRowsDiscarded: Int
    /// This is deliberately fixed at zero in ledger-primary mode.  Codex
    /// session observations are a fallback source, never an additive source.
    let codexSessionRowsAdded: Int
    let unknownRouteRecordCount: Int
    let streamAbortedRecordCount: Int
}

struct OpenCodexStandardReferenceSummary: Equatable, Sendable {
    let pricedRecordCount: Int
    let totalPicoUSD: Int64?
    let aggregateOverflowed: Bool
    let priceBasis: String

    var totalUSD: String? {
        guard let totalPicoUSD else { return nil }
        return AILSA_SSStandardReferenceEstimate(
            status: .referenceEstimate,
            picoUSD: totalPicoUSD,
            priceBasis: OpenCodexStandardReferenceEstimator.priceBasis,
            leaf: nil,
            contextLadder: nil,
            estimatePartial: false,
            fastGranted: nil,
            confirmedServiceTier: nil,
            identityAssumption: OpenCodexStandardReferenceIdentityAssumption(
                provider: nil,
                resolvedModel: nil,
                requestedModel: nil,
                modelEcho: nil,
                usedModelFallback: false,
                confirmed: false
            ),
            contextTierAssumption: OpenCodexStandardReferenceContextTierAssumption(
                confirmation: nil,
                responseServiceTier: nil,
                fastOutcome: nil,
                fastGranted: nil,
                confirmedServiceTier: nil,
                ladder: nil,
                inputTokens: nil,
                thresholdKind: nil,
                thresholdValue: nil,
                silentShortApplied: false
            )
        ).apiEquivalentUSD
    }
}

struct OpenCodexLedgerAnalytics: Equatable, Sendable {
    let records: [OpenCodexLedgerMeteringRecord]
    let source: OpenCodexLedgerSource
    /// Local completion time for this read, not the latest usage event time.
    let scannedAt: Date
    let coverage: OpenCodexLedgerCoverage
    /// Nil means there were no exact-priced records; it is distinct from an
    /// exact zero amount from one or more reported zero-token records.
    let exactAPIEquivalentPicoUSD: Int64?
    let exactAPIEquivalentAggregateOverflowed: Bool
    /// Nil means no separately estimated records were priced.
    let estimatedAPIEquivalentPicoUSD: Int64?
    let estimatedAPIEquivalentAggregateOverflowed: Bool
    /// Separately disclosed v1 standard-reference aggregate. This is not an
    /// actual invoice or a replacement for confirmed-tier pricing.
    let standardReference: OpenCodexStandardReferenceSummary

    var exactAPIEquivalentUSD: String? {
        guard let exactAPIEquivalentPicoUSD else { return nil }
        return OpenCodexAPIEquivalent(
            status: .priced,
            valueKind: .exactDerived,
            picoUSD: exactAPIEquivalentPicoUSD,
            catalogBindingID: nil,
            catalogVersion: nil,
            officialSourceURL: nil
        ).apiEquivalentUSD
    }

    var estimatedAPIEquivalentUSD: String? {
        guard let estimatedAPIEquivalentPicoUSD else { return nil }
        return OpenCodexAPIEquivalent(
            status: .estimatedUsage,
            valueKind: .estimated,
            picoUSD: estimatedAPIEquivalentPicoUSD,
            catalogBindingID: nil,
            catalogVersion: nil,
            officialSourceURL: nil
        ).apiEquivalentUSD
    }
}

// MARK: - Audited, exact pricing catalog

/// A catalog rule may be used only if the recorded request input belongs to
/// its explicit official context range. These are conditions, not aliases;
/// unsupported condition shapes never become a binding.
enum OpenCodexPricingInputTokenCondition: Equatable, Sendable {
    case allContexts
    case inputTokensLessThanOrEqual(Int)
    case inputTokensGreaterThan(Int)
    case promptTokensLessThan(Int)
    case promptTokensGreaterThanOrEqual(Int)

    func matches(_ inputTokens: Int) -> Bool {
        switch self {
        case .allContexts:
            true
        case .inputTokensLessThanOrEqual(let value):
            inputTokens <= value
        case .inputTokensGreaterThan(let value):
            inputTokens > value
        case .promptTokensLessThan(let value):
            inputTokens < value
        case .promptTokensGreaterThanOrEqual(let value):
            inputTokens >= value
        }
    }
}

struct OpenCodexPricingCatalog: Sendable {
    struct Binding: Equatable, Sendable {
        let bindingID: String
        /// Every audited binding identifier that supplied this exact,
        /// semantically identical quote. Most bindings have exactly one ID;
        /// the catalog loader only coalesces duplicate IDs when every retained
        /// pricing field and source URL is identical.
        let sourceBindingIDs: [String]
        let provider: String
        let resolvedModel: String
        let serviceTier: String?
        let inputTokenCondition: OpenCodexPricingInputTokenCondition
        let status: OpenCodexPricingCatalogEntryStatus
        let currency: String
        let inputPicoUSDPerToken: Int64?
        let cachedInputPicoUSDPerToken: Int64?
        let outputPicoUSDPerToken: Int64?
        let cacheInputHandling: OpenCodexCacheInputHandling?
        let reasoningOutputIsSubset: Bool?
        let officialSourceURL: String?

        init(
            bindingID: String,
            sourceBindingIDs: [String] = [],
            provider: String,
            resolvedModel: String,
            serviceTier: String? = nil,
            inputTokenCondition: OpenCodexPricingInputTokenCondition = .allContexts,
            status: OpenCodexPricingCatalogEntryStatus,
            currency: String = "USD",
            inputPicoUSDPerToken: Int64? = nil,
            cachedInputPicoUSDPerToken: Int64? = nil,
            outputPicoUSDPerToken: Int64? = nil,
            cacheInputHandling: OpenCodexCacheInputHandling? = nil,
            reasoningOutputIsSubset: Bool? = nil,
            officialSourceURL: String? = nil
        ) {
            self.bindingID = bindingID
            self.sourceBindingIDs = (sourceBindingIDs.isEmpty ? [bindingID] : sourceBindingIDs)
                .sorted()
            self.provider = provider
            self.resolvedModel = resolvedModel
            self.serviceTier = Self.normalizedTier(serviceTier)
            self.inputTokenCondition = inputTokenCondition
            self.status = status
            self.currency = currency
            self.inputPicoUSDPerToken = inputPicoUSDPerToken
            self.cachedInputPicoUSDPerToken = cachedInputPicoUSDPerToken
            self.outputPicoUSDPerToken = outputPicoUSDPerToken
            self.cacheInputHandling = cacheInputHandling
            self.reasoningOutputIsSubset = reasoningOutputIsSubset
            self.officialSourceURL = officialSourceURL
        }

        fileprivate static func normalizedTier(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    enum Lookup: Sendable {
        case found(Binding)
        case missing
        case ambiguous
    }

    let schema: String
    let catalogVersion: String
    let provenance: Provenance?
    let bindings: [Binding]

    /// Extracts the `audit=yyyy-MM-dd` component that
    /// `AILSA_SSVerifiedPricingCatalogLoader` stamps into `catalogVersion`.
    static func auditDate(fromCatalogVersion version: String?) -> String? {
        guard let version else { return nil }
        for part in version.split(separator: "|") where part.hasPrefix("audit=") {
            let value = String(part.dropFirst("audit=".count))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    struct Provenance: Equatable, Sendable {
        let artifactPath: String
        let generatedAt: String
        let auditDate: String
        let sourceAuditSchemaVersion: Int
        let acceptedBindingCount: Int
        /// Number of redundant source IDs that were coalesced only after an
        /// exact semantic-and-source equality check; this is never alias
        /// matching or a fallback lookup.
        let equivalentDuplicateBindingCount: Int
    }

    init(
        schema: String = "ailsa.opencodex.pricing.v1",
        catalogVersion: String,
        provenance: Provenance? = nil,
        bindings: [Binding]
    ) {
        self.schema = schema
        self.catalogVersion = catalogVersion
        self.provenance = provenance
        self.bindings = bindings
    }

    static let empty = OpenCodexPricingCatalog(catalogVersion: "unavailable", bindings: [])

    /// Exact tuple lookup only.  In particular, this deliberately does not
    /// trim provider/model aliases, fall back to requestedModel, or infer a
    /// default tier for an explicitly tiered record.
    func lookup(
        provider: String,
        resolvedModel: String,
        serviceTier: String?,
        inputTokens: Int
    ) -> Lookup {
        let normalizedTier = Binding.normalizedTier(serviceTier)
        let matches = bindings.filter {
            $0.provider == provider
                && $0.resolvedModel == resolvedModel
                && $0.serviceTier == normalizedTier
                && $0.inputTokenCondition.matches(inputTokens)
        }
        switch matches.count {
        case 0:
            return .missing
        case 1:
            return .found(matches[0])
        default:
            return .ambiguous
        }
    }
}

// MARK: - Ledger reader

/// Read-only reference implementation for `~/.opencodex/usage.jsonl`.
///
/// It reads no account/token files and never sends data to a service.  The
/// production adapter can call `read(data:)` after loading the ledger with its
/// existing local file boundary.
struct AILSA_SSLedgerMeteringReader: Sendable {
    private let pricingCatalog: OpenCodexPricingCatalog
    private let standardReferenceEstimator: OpenCodexStandardReferenceEstimator

    init(
        pricingCatalog: OpenCodexPricingCatalog,
        standardReferenceEstimator: OpenCodexStandardReferenceEstimator = .init()
    ) {
        self.pricingCatalog = pricingCatalog
        self.standardReferenceEstimator = standardReferenceEstimator
    }

    /// Pricing bases this reader can apply, each with its own verification date.
    var pricingProvenance: [QuotaPricingProvenance] {
        var result = [QuotaPricingProvenance(basis: .standardReference, auditDate: OpenCodexStandardReferenceEstimator.auditDate)]
        if let provenance = pricingCatalog.provenance {
            result.append(QuotaPricingProvenance(basis: .verifiedCatalog, auditDate: provenance.auditDate))
        }
        return result
    }

    struct State: Sendable {
        var ledgerRowsSeen = 0
        var malformedLedgerRows = 0
        var rowsMissingRequestID = 0
        var rowsMissingTimestamp = 0
        var duplicateRowsDiscarded = 0
        fileprivate var candidates: [String: Winner] = [:]
        fileprivate var records: [String: OpenCodexLedgerMeteringRecord] = [:]
    }

    func read(data: Data, scannedAt: Date? = nil) -> OpenCodexLedgerAnalytics {
        var state = State()
        append(data: data, to: &state)
        return result(state: state, scannedAt: scannedAt)
    }

    /// Caller supplies complete lines. Parsing and winner selection are identical
    /// for a full file and a sequence of append chunks.
    func append(data: Data, to state: inout State) {
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            let ordinal = state.ledgerRowsSeen
            state.ledgerRowsSeen += 1
            guard let root = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] else {
                state.malformedLedgerRows += 1
                continue
            }
            guard let requestID = Self.nonemptyString(root["requestId"]) else {
                state.rowsMissingRequestID += 1
                continue
            }
            guard let occurredAt = Self.date(root["timestamp"]) else {
                state.rowsMissingTimestamp += 1
                continue
            }

            let usage = root["usage"] as? [String: Any]
            let tierOutcome = root["tierOutcome"] as? [String: Any] ?? [:]
            let tierOutcomeConfirmation = Self.nonemptyString(tierOutcome["confirmation"])
            let tierOutcomeCanonical = Self.nonemptyString(tierOutcome["canonical"])
            let responseServiceTier = Self.nonemptyString(root["responseServiceTier"])
                ?? Self.nonemptyString(root["response_service_tier"])
            let explicitConfirmedTier = Self.nonemptyString(root["confirmedServiceTier"])
                ?? Self.nonemptyString(root["confirmed_service_tier"])
            let validatedTierOutcome = Self.validatedTierOutcome(
                root: root,
                tierOutcomeConfirmation: tierOutcomeConfirmation,
                tierOutcomeCanonical: tierOutcomeCanonical,
                explicitConfirmedTier: explicitConfirmedTier
            )
            let candidate = Candidate(
                requestID: requestID,
                occurredAt: occurredAt,
                ordinal: ordinal,
                provider: Self.nonemptyString(root["provider"]),
                requestedModel: Self.nonemptyString(root["requestedModel"]),
                resolvedModel: Self.nonemptyString(root["resolvedModel"]),
                modelEcho: Self.nonemptyString(root["model"]),
                requestedServiceTier: Self.nonemptyString(root["requestedServiceTier"])
                    ?? Self.nonemptyString(root["requested_service_tier"]),
                confirmedServiceTier: validatedTierOutcome.confirmedServiceTier,
                tierOutcomeConfirmation: tierOutcomeConfirmation,
                tierOutcomeCanonical: tierOutcomeCanonical,
                responseServiceTier: responseServiceTier,
                fastOutcome: Self.nonemptyString(tierOutcome["fastOutcome"])
                    ?? Self.nonemptyString(root["fastOutcome"])
                    ?? Self.nonemptyString(root["fast_outcome"]),
                fastGrantEvidence: validatedTierOutcome.fastGrantEvidence,
                requestedEffort: Self.nonemptyString(root["requestedEffort"]),
                effectiveEffort: Self.nonemptyString(root["effectiveEffort"]),
                usageStatus: OpenCodexUsageStatus(rawValue: Self.nonemptyString(root["usageStatus"]) ?? "") ?? .unsupported,
                usageEstimated: (usage?["estimated"] as? Bool) == true,
                currency: Self.nonemptyString(root["currency"])
                    ?? Self.nonemptyString(root["currencyCode"])
                    ?? Self.nonemptyString(usage?["currency"]),
                apiEquivalentEligibility: Self.nonemptyString(root["apiEquivalentEligibility"])
                    ?? Self.nonemptyString(root["api_equivalent_eligibility"]),
                streamAborted: (root["streamAborted"] as? Bool) == true
                    || (root["stream_aborted"] as? Bool) == true,
                parsedTokens: Self.parseTokens(usage)
            )

            if let existing = state.candidates[requestID] {
                state.duplicateRowsDiscarded += 1
                if candidate.isPreferred(over: existing) {
                    state.candidates[requestID] = Winner(rank: candidate.snapshotRank, occurredAt: candidate.occurredAt, ordinal: candidate.ordinal)
                    state.records[requestID] = makeRecord(from: candidate)
                }
            } else {
                state.candidates[requestID] = Winner(rank: candidate.snapshotRank, occurredAt: candidate.occurredAt, ordinal: candidate.ordinal)
                    state.records[requestID] = makeRecord(from: candidate)
            }
        }

    }

    func drainChangedRecords(_ state: inout State) -> [String: OpenCodexLedgerMeteringRecord] {
        let records = state.records
        state.records = [:]
        return records
    }
    func result(state: State, scannedAt: Date? = nil) -> OpenCodexLedgerAnalytics {
        let ledgerRowsSeen = state.ledgerRowsSeen
        let malformedLedgerRows = state.malformedLedgerRows
        let rowsMissingRequestID = state.rowsMissingRequestID
        let rowsMissingTimestamp = state.rowsMissingTimestamp
        let duplicateRowsDiscarded = state.duplicateRowsDiscarded
        let records = state.records.values.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
            return $0.requestID < $1.requestID
        }
        let nonAbortedRecords = records.filter { !$0.streamAborted }
        let meteredRecords = nonAbortedRecords.filter {
            $0.usageStatus == .reported
                && $0.tokenSource == .upstreamReported
                && $0.tokens.hasPrimaryTokens
        }
        let exactPricedRecords = meteredRecords.filter { $0.pricing.status == .priced }
        let standardReferencePricedRecords = meteredRecords.filter {
            $0.standardReferenceEstimate.status == .referenceEstimate
        }
        let validRequestIDRows = ledgerRowsSeen - malformedLedgerRows - rowsMissingRequestID - rowsMissingTimestamp
        let pricingTokenDenominator = Self.checkedTokenSum(meteredRecords.compactMap(\.tokens.totalTokens))
        let pricingTokenNumerator = Self.checkedTokenSum(exactPricedRecords.compactMap(\.tokens.totalTokens))
        let pricingTokenVolumeOverflowed = pricingTokenDenominator == nil || pricingTokenNumerator == nil
        let exactAmounts = records.compactMap { $0.pricing.status == .priced ? $0.pricing.picoUSD : nil }
        let estimatedAmounts = records.compactMap { $0.pricing.status == .estimatedUsage ? $0.pricing.picoUSD : nil }
        let standardReferenceAmounts = records.compactMap {
            $0.standardReferenceEstimate.status == .referenceEstimate
                ? $0.standardReferenceEstimate.picoUSD
                : nil
        }
        let exactTotal = exactAmounts.isEmpty ? nil : Self.sumPicoUSD(exactAmounts)
        let estimatedTotal = estimatedAmounts.isEmpty ? nil : Self.sumPicoUSD(estimatedAmounts)
        let standardReferenceTotal = standardReferenceAmounts.isEmpty
            ? nil
            : OpenCodexStandardReferenceEstimator.checkedPicoUSDSum(standardReferenceAmounts)

        return OpenCodexLedgerAnalytics(
            records: records,
            source: .canonicalLedger,
            scannedAt: scannedAt ?? Date(),
            coverage: OpenCodexLedgerCoverage(
                tokenMeteringRecordCoverage: OpenCodexCoverageRatio(
                    numerator: meteredRecords.count,
                    denominator: nonAbortedRecords.count,
                    unit: .records,
                    definition: "reported primary-token records divided by canonical non-aborted request records"
                ),
                pricingRecordCoverage: OpenCodexCoverageRatio(
                    numerator: exactPricedRecords.count,
                    denominator: meteredRecords.count,
                    unit: .records,
                    definition: "exact-priced records divided by reported primary-token records"
                ),
                pricingTokenVolumeCoverage: OpenCodexCoverageRatio(
                    numerator: pricingTokenNumerator ?? 0,
                    denominator: pricingTokenDenominator ?? 0,
                    unit: .tokens,
                    definition: "primary tokens in exact-priced records divided by primary tokens in reported primary-token records; unavailable on checked aggregate overflow"
                ),
                pricingTokenVolumeOverflowed: pricingTokenVolumeOverflowed,
                standardReferenceRecordCoverage: OpenCodexCoverageRatio(
                    numerator: standardReferencePricedRecords.count,
                    denominator: meteredRecords.count,
                    unit: .records,
                    definition: "official standard-reference priced records divided by reported primary-token records; not an invoice or confirmed-tier coverage"
                ),
                dedupeRequestIDCoverage: OpenCodexCoverageRatio(
                    numerator: validRequestIDRows,
                    denominator: ledgerRowsSeen,
                    unit: .records,
                    definition: "ledger rows carrying a non-empty requestId and timestamp divided by all non-empty ledger rows seen"
                ),
                ledgerRowsSeen: ledgerRowsSeen,
                malformedLedgerRows: malformedLedgerRows,
                ledgerRowsMissingRequestID: rowsMissingRequestID,
                ledgerRowsMissingTimestamp: rowsMissingTimestamp,
                ledgerDuplicateRowsDiscarded: duplicateRowsDiscarded,
                codexSessionRowsAdded: 0,
                unknownRouteRecordCount: records.filter { $0.routeIdentityStatus != .resolved }.count,
                streamAbortedRecordCount: records.filter(\.streamAborted).count
            ),
            exactAPIEquivalentPicoUSD: exactTotal,
            exactAPIEquivalentAggregateOverflowed: !exactAmounts.isEmpty && exactTotal == nil,
            estimatedAPIEquivalentPicoUSD: estimatedTotal,
            estimatedAPIEquivalentAggregateOverflowed: !estimatedAmounts.isEmpty && estimatedTotal == nil,
            standardReference: OpenCodexStandardReferenceSummary(
                pricedRecordCount: standardReferencePricedRecords.count,
                totalPicoUSD: standardReferenceTotal,
                aggregateOverflowed: !standardReferenceAmounts.isEmpty && standardReferenceTotal == nil,
                priceBasis: OpenCodexStandardReferenceEstimator.priceBasis
            )
        )
    }

    private func makeRecord(from candidate: Candidate) -> OpenCodexLedgerMeteringRecord {
        let identityStatus: OpenCodexRouteIdentityStatus
        if candidate.provider != nil && candidate.resolvedModel != nil {
            identityStatus = .resolved
        } else if candidate.requestedModel != nil {
            identityStatus = .requestedOnly
        } else {
            identityStatus = .unknown
        }

        let tokens = candidate.parsedTokens.tokens
        let tokenSource: OpenCodexTokenSource
        switch candidate.usageStatus {
        case .reported where tokens.hasPrimaryTokens:
            tokenSource = .upstreamReported
        case .estimated where tokens.hasPrimaryTokens:
            tokenSource = .upstreamEstimated
        case .reported, .estimated, .unreported, .unsupported:
            tokenSource = .unavailable
        }

        let pricing = price(
            candidate: candidate,
            identityStatus: identityStatus,
            tokens: tokens,
            tokenSource: tokenSource
        )
        let standardReferenceEstimate = standardReferenceEstimator.estimate(
            OpenCodexStandardReferenceInput(
                provider: candidate.provider,
                resolvedModel: candidate.resolvedModel,
                requestedModel: candidate.requestedModel,
                modelEcho: candidate.modelEcho,
                usageStatus: candidate.usageStatus,
                usageEstimated: candidate.usageEstimated,
                streamAborted: candidate.streamAborted,
                currency: candidate.currency,
                apiEquivalentEligibility: candidate.apiEquivalentEligibility,
                tierOutcomeConfirmation: candidate.tierOutcomeConfirmation,
                tierOutcomeCanonical: candidate.tierOutcomeCanonical,
                responseServiceTier: candidate.responseServiceTier,
                fastOutcome: candidate.fastOutcome,
                confirmedServiceTier: candidate.confirmedServiceTier,
                fastGrantEvidence: candidate.fastGrantEvidence,
                tokens: tokens,
                tokenSemanticIssue: candidate.parsedTokens.semanticIssue != nil,
                occurredAt: candidate.occurredAt
            )
        )
        return OpenCodexLedgerMeteringRecord(
            requestID: candidate.requestID,
            occurredAt: candidate.occurredAt,
            source: .canonicalLedger,
            requestedModel: candidate.requestedModel,
            resolvedModel: candidate.resolvedModel,
            modelEcho: candidate.modelEcho,
            displayModel: candidate.resolvedModel ?? candidate.requestedModel,
            routeProvider: candidate.provider,
            routeIdentityStatus: identityStatus,
            requestedServiceTier: candidate.requestedServiceTier,
            confirmedServiceTier: candidate.confirmedServiceTier,
            fastGranted: candidate.fastGrantEvidence.fastGranted,
            fastGrantEvidence: candidate.fastGrantEvidence,
            tierOutcomeConfirmation: candidate.tierOutcomeConfirmation,
            tierOutcomeCanonical: candidate.tierOutcomeCanonical,
            responseServiceTier: candidate.responseServiceTier,
            fastOutcome: candidate.fastOutcome,
            requestedEffort: candidate.requestedEffort,
            effectiveEffort: candidate.effectiveEffort,
            usageStatus: candidate.usageStatus,
            tokenSource: tokenSource,
            tokens: tokens,
            pricing: pricing,
            standardReferenceEstimate: standardReferenceEstimate,
            streamAborted: candidate.streamAborted
        )
    }

    private func price(
        candidate: Candidate,
        identityStatus: OpenCodexRouteIdentityStatus,
        tokens: OpenCodexUsageTokens,
        tokenSource: OpenCodexTokenSource
    ) -> OpenCodexAPIEquivalent {
        if candidate.streamAborted {
            return .unavailable(.streamAborted)
        }
        switch candidate.usageStatus {
        case .unreported:
            return .unavailable(.usageUnavailable)
        case .unsupported:
            return .unavailable(.unsupported)
        case .reported, .estimated:
            break
        }
        guard tokenSource != .unavailable, tokens.hasPrimaryTokens else {
            return .unavailable(.usageUnavailable)
        }
        guard identityStatus == .resolved,
              let provider = candidate.provider,
              let resolvedModel = candidate.resolvedModel
        else {
            return .unavailable(.modelUnresolved)
        }
        guard let confirmedServiceTier = candidate.confirmedServiceTier,
              Self.confirmedTierMatchesFastEvidence(
                confirmedServiceTier,
                evidence: candidate.fastGrantEvidence
              )
        else {
            return .unavailable(.priceUnknown)
        }
        guard candidate.parsedTokens.semanticIssue == nil else {
            return .unavailable(.usageSemanticsConflict)
        }
        guard let inputTokens = tokens.inputTokens else {
            return .unavailable(.usageUnavailable)
        }

        switch pricingCatalog.lookup(
            provider: provider,
            resolvedModel: resolvedModel,
            serviceTier: confirmedServiceTier,
            inputTokens: inputTokens
        ) {
        case .missing, .ambiguous:
            return .unavailable(.priceUnknown)
        case .found(let binding):
            guard binding.status == .verified else {
                return .unavailable(binding.status == .unsupported ? .unsupported : .priceUnknown)
            }
            guard binding.currency == "USD",
                  binding.reasoningOutputIsSubset == true,
                  let amount = Self.exactPicoUSD(tokens: tokens, binding: binding)
            else {
                return .unavailable(.priceUnknown)
            }
            return OpenCodexAPIEquivalent(
                status: candidate.usageStatus == .reported ? .priced : .estimatedUsage,
                valueKind: candidate.usageStatus == .reported ? .exactDerived : .estimated,
                picoUSD: amount,
                catalogBindingID: binding.bindingID,
                catalogVersion: pricingCatalog.catalogVersion,
                officialSourceURL: binding.officialSourceURL
            )
        }
    }

    /// Returns nil when a catalog does not supply enough evidence to price the
    /// emitted breakdown.  In particular, cache creation is intentionally not
    /// guessed under v1 because no non-overlap rule is present in the producer
    /// contract.
    private static func exactPicoUSD(
        tokens: OpenCodexUsageTokens,
        binding: OpenCodexPricingCatalog.Binding
    ) -> Int64? {
        guard let input = tokens.inputTokens,
              let output = tokens.outputTokens,
              let inputRate = binding.inputPicoUSDPerToken,
              let outputRate = binding.outputPicoUSDPerToken,
              (tokens.cacheCreationInputTokens ?? 0) == 0
        else {
            return nil
        }

        let cached = tokens.cachedInputTokens ?? tokens.cacheReadInputTokens ?? 0
        let inputCost: Int64?
        switch binding.cacheInputHandling {
        case .embeddedAtInputRate:
            inputCost = checkedProduct(input, inputRate)
        case .cachedSubsetDiscounted:
            guard cached <= input,
                  let cacheRate = binding.cachedInputPicoUSDPerToken,
                  let uncachedCost = checkedProduct(input - cached, inputRate),
                  let cachedCost = checkedProduct(cached, cacheRate)
            else {
                return nil
            }
            inputCost = checkedSum(uncachedCost, cachedCost)
        case nil:
            return nil
        }
        guard let inputCost,
              let outputCost = checkedProduct(output, outputRate)
        else {
            return nil
        }
        return checkedSum(inputCost, outputCost)
    }

    private static func checkedProduct(_ tokens: Int, _ picoUSDPerToken: Int64) -> Int64? {
        guard tokens >= 0, picoUSDPerToken >= 0 else { return nil }
        let (value, overflow) = Int64(tokens).multipliedReportingOverflow(by: picoUSDPerToken)
        return overflow ? nil : value
    }

    private static func checkedSum(_ lhs: Int64, _ rhs: Int64) -> Int64? {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? nil : value
    }

    private static func sumPicoUSD(_ values: [Int64]) -> Int64? {
        var result: Int64 = 0
        for value in values {
            guard let sum = checkedSum(result, value) else { return nil }
            result = sum
        }
        return result
    }

    private static func checkedTokenSum(_ values: [Int]) -> Int? {
        var result = 0
        for value in values {
            let sum = result.addingReportingOverflow(value)
            guard !sum.overflow else { return nil }
            result = sum.partialValue
        }
        return result
    }

    private static func confirmedTierMatchesFastEvidence(
        _ tier: String,
        evidence: OpenCodexFastGrantEvidence
    ) -> Bool {
        let normalized = tier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let tierIsFast = ["fast", "priority", "ultrafast"].contains(normalized)
        switch evidence {
        case .unknown:
            return false
        case .explicitlyGranted:
            return tierIsFast
        case .explicitlyNotGranted:
            return !tierIsFast
        }
    }

    fileprivate struct Winner: Sendable {
        let rank: Int
        let occurredAt: Date
        let ordinal: Int
    }

    fileprivate struct Candidate: Sendable {
        let requestID: String
        let occurredAt: Date
        let ordinal: Int
        let provider: String?
        let requestedModel: String?
        let resolvedModel: String?
        let modelEcho: String?
        let requestedServiceTier: String?
        let confirmedServiceTier: String?
        let tierOutcomeConfirmation: String?
        let tierOutcomeCanonical: String?
        let responseServiceTier: String?
        let fastOutcome: String?
        let fastGrantEvidence: OpenCodexFastGrantEvidence
        let requestedEffort: String?
        let effectiveEffort: String?
        let usageStatus: OpenCodexUsageStatus
        let usageEstimated: Bool
        let currency: String?
        let apiEquivalentEligibility: String?
        let streamAborted: Bool
        let parsedTokens: ParsedTokens

        /// Same requestId is one logical turn.  Prefer a client-received
        /// reported result; never merge its physical attempts.
        func isPreferred(over other: Winner) -> Bool {
            let rank = snapshotRank
            let otherRank = other.rank
            if rank != otherRank { return rank > otherRank }
            if occurredAt != other.occurredAt { return occurredAt > other.occurredAt }
            return ordinal > other.ordinal
        }

        var snapshotRank: Int {
            let clientSuccess = streamAborted ? 0 : 10
            let status = switch usageStatus {
            case .reported: 4
            case .estimated: 3
            case .unreported: 2
            case .unsupported: 1
            }
            let usage = parsedTokens.tokens.hasPrimaryTokens ? 1 : 0
            return clientSuccess + status + usage
        }
    }

    fileprivate struct ParsedTokens: Sendable {
        let tokens: OpenCodexUsageTokens
        let semanticIssue: SemanticIssue?

        enum SemanticIssue: Sendable {
            case invalidPrimaryTokens
            case totalMismatch
            case cacheMismatch
            case cacheOutsideInput
            case reasoningOutsideOutput
        }
    }

    private static func parseTokens(_ rawValue: Any?) -> ParsedTokens {
        guard let raw = rawValue as? [String: Any],
              let input = nonnegativeInt(raw["inputTokens"]),
              let output = nonnegativeInt(raw["outputTokens"])
        else {
            return ParsedTokens(tokens: .unavailable, semanticIssue: .invalidPrimaryTokens)
        }

        let declaredTotal = nonnegativeInt(raw["totalTokens"])
        let computedTotal = input.addingReportingOverflow(output)
        guard !computedTotal.overflow else {
            return ParsedTokens(tokens: .unavailable, semanticIssue: .invalidPrimaryTokens)
        }
        let cached = optionalNonnegativeInt(raw["cachedInputTokens"])
        let cacheRead = optionalNonnegativeInt(raw["cacheReadInputTokens"])
        let cacheCreation = optionalNonnegativeInt(raw["cacheCreationInputTokens"])
        let reasoning = optionalNonnegativeInt(raw["reasoningOutputTokens"])
        let tokens = OpenCodexUsageTokens(
            inputTokens: input,
            outputTokens: output,
            totalTokens: computedTotal.partialValue,
            cachedInputTokens: cached.value,
            cacheReadInputTokens: cacheRead.value,
            cacheCreationInputTokens: cacheCreation.value,
            reasoningOutputTokens: reasoning.value,
            totalSemantics: .inputPlusOutput
        )

        if declaredTotal != nil && declaredTotal != computedTotal.partialValue {
            return ParsedTokens(tokens: tokens, semanticIssue: .totalMismatch)
        }
        if !cached.isValid || !cacheRead.isValid || !cacheCreation.isValid || !reasoning.isValid {
            return ParsedTokens(tokens: tokens, semanticIssue: .invalidPrimaryTokens)
        }
        if let cached = cached.value, let cacheRead = cacheRead.value, cached != cacheRead {
            return ParsedTokens(tokens: tokens, semanticIssue: .cacheMismatch)
        }
        if [cached.value, cacheRead.value, cacheCreation.value].compactMap({ $0 }).contains(where: { $0 > input }) {
            return ParsedTokens(tokens: tokens, semanticIssue: .cacheOutsideInput)
        }
        if let reasoning = reasoning.value, reasoning > output {
            return ParsedTokens(tokens: tokens, semanticIssue: .reasoningOutsideOutput)
        }
        return ParsedTokens(tokens: tokens, semanticIssue: nil)
    }

    private static func optionalNonnegativeInt(_ value: Any?) -> (value: Int?, isValid: Bool) {
        guard value != nil else { return (nil, true) }
        guard let parsed = nonnegativeInt(value) else { return (nil, false) }
        return (parsed, true)
    }

    private static func nonnegativeInt(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            // JSONSerialization bridges every JSON number through NSNumber.
            // In particular, NSNumber(value: 0) may look like Bool through
            // Swift/Objective-C bridges, so inspect the semantic CF type.
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            let double = number.doubleValue
            guard double.isFinite,
                  double >= 0,
                  double.rounded(.towardZero) == double,
                  double <= Double(Int.max)
            else { return nil }
            return Int(double)
        }
        if let integer = value as? Int, integer >= 0 { return integer }
        if let string = value as? String, let integer = Int(string), integer >= 0 {
            return integer
        }
        return nil
    }

    private static func isVendorTierConfirmation(_ value: String?) -> Bool {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "vendor", "granted":
            true
        default:
            false
        }
    }

    /// Reconcile only provider-confirmed tier evidence. A bridge-provided
    /// boolean can corroborate that evidence, but it cannot create it; a
    /// missing, null, malformed, or contradictory alias must never become an
    /// implicit `false` grant.
    private static func validatedTierOutcome(
        root: [String: Any],
        tierOutcomeConfirmation: String?,
        tierOutcomeCanonical: String?,
        explicitConfirmedTier: String?
    ) -> ValidatedTierOutcome {
        guard isVendorTierConfirmation(tierOutcomeConfirmation) else {
            return .unknown
        }
        guard let tier = reconciledTier(
            canonical: tierOutcomeCanonical,
            explicit: explicitConfirmedTier
        ) else {
            return .unknown
        }
        let normalized = tier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return .unknown }
        let derivedEvidence: OpenCodexFastGrantEvidence = ["fast", "priority", "ultrafast"].contains(normalized)
            ? .explicitlyGranted
            : .explicitlyNotGranted
        switch rawFastGrantSignal(root) {
        case .absent:
            return ValidatedTierOutcome(
                confirmedServiceTier: tier,
                fastGrantEvidence: derivedEvidence
            )
        case .value(let rawValue) where rawValue == derivedEvidence.fastGranted:
            return ValidatedTierOutcome(
                confirmedServiceTier: tier,
                fastGrantEvidence: derivedEvidence
            )
        case .value, .nullOrMalformed, .conflictingAliases:
            return .unknown
        }
    }

    private static func reconciledTier(canonical: String?, explicit: String?) -> String? {
        guard let selected = canonical ?? explicit else { return nil }
        guard let canonical, let explicit else { return selected }
        return canonical.caseInsensitiveCompare(explicit) == .orderedSame ? selected : nil
    }

    private static func rawFastGrantSignal(_ root: [String: Any]) -> RawFastGrantSignal {
        let aliases = ["fastGranted", "fast_granted"]
        var values: [Bool] = []
        var hasAnyAlias = false
        var hasNullOrMalformedAlias = false
        for key in aliases where root.keys.contains(key) {
            hasAnyAlias = true
            guard let value = root[key], !(value is NSNull), let bool = value as? Bool else {
                hasNullOrMalformedAlias = true
                continue
            }
            values.append(bool)
        }
        guard hasAnyAlias else { return .absent }
        guard !hasNullOrMalformedAlias, let first = values.first else {
            return .nullOrMalformed
        }
        return values.allSatisfy { $0 == first }
            ? .value(first)
            : .conflictingAliases
    }

    private struct ValidatedTierOutcome {
        let confirmedServiceTier: String?
        let fastGrantEvidence: OpenCodexFastGrantEvidence

        static let unknown = ValidatedTierOutcome(
            confirmedServiceTier: nil,
            fastGrantEvidence: .unknown
        )
    }

    private enum RawFastGrantSignal {
        case absent
        case value(Bool)
        case nullOrMalformed
        case conflictingAliases
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber, !(value is Bool) {
            let timestamp = number.doubleValue
            guard timestamp.isFinite else { return nil }
            return Date(timeIntervalSince1970: timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp)
        }
        guard let string = value as? String else { return nil }
        // These formatters are short-lived by design.  A shared mutable
        // ISO8601DateFormatter would make this Sendable reader depend on
        // Foundation formatter concurrency annotations.
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: string)
    }
}

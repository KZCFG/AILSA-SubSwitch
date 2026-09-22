import Foundation

/// ATC v1's additive, official-standard token reference. This value is not an
/// invoice and deliberately never changes the strict confirmed-tier price path.
enum OpenCodexStandardReferenceStatus: String, Sendable {
    case referenceEstimate = "reference_estimate"
    case aborted
    case unreported
    case estimatedUsage = "estimated_usage"
    case unknownIdentity = "unknown_identity"
    case unknownPrice = "unknown_price"
    case unreportedTokens = "unreported_tokens"
    case overThresholdNoLongLeaf = "over_threshold_no_long_leaf"
    case fastNotInStandardReference = "fast_not_in_standard_reference"
    case usageSemanticsConflict = "usage_semantics_conflict"
    case nonUSD = "non_usd"
}

struct OpenCodexStandardReferenceIdentityAssumption: Equatable, Sendable {
    let provider: String?
    let resolvedModel: String?
    let requestedModel: String?
    let modelEcho: String?
    /// Must remain false. `model` and `requestedModel` never repair identity.
    let usedModelFallback: Bool
    let confirmed: Bool
}

struct OpenCodexStandardReferenceContextTierAssumption: Equatable, Sendable {
    let confirmation: String?
    let responseServiceTier: String?
    let fastOutcome: String?
    /// `nil` is an unknown Fast outcome, distinct from a vendor-confirmed
    /// non-Fast result.
    let fastGranted: Bool?
    let confirmedServiceTier: String?
    let ladder: String?
    let inputTokens: Int?
    let thresholdKind: String?
    let thresholdValue: Int?
    let silentShortApplied: Bool
}

struct AILSA_SSStandardReferenceEstimate: Equatable, Sendable {
    let status: OpenCodexStandardReferenceStatus
    /// USD * 10^12; keep integer arithmetic through aggregation and only round
    /// at the presentation boundary.
    let picoUSD: Int64?
    let priceBasis: String?
    let leaf: String?
    let contextLadder: String?
    let estimatePartial: Bool
    let fastGranted: Bool?
    let confirmedServiceTier: String?
    let identityAssumption: OpenCodexStandardReferenceIdentityAssumption
    let contextTierAssumption: OpenCodexStandardReferenceContextTierAssumption

    var apiEquivalentUSD: String? {
        guard let picoUSD else { return nil }
        let scale: Int64 = 1_000_000_000_000
        let whole = picoUSD / scale
        let fraction = picoUSD % scale
        return "\(whole).\(String(format: "%012lld", fraction))"
    }
}

/// This input carries both raw disclosure fields and the ledger reader's
/// reconciled, three-state tier result. The estimator must not re-infer a
/// concrete tier from an unconfirmed raw alias.
struct OpenCodexStandardReferenceInput: Sendable {
    let provider: String?
    let resolvedModel: String?
    let requestedModel: String?
    let modelEcho: String?
    let usageStatus: OpenCodexUsageStatus
    let usageEstimated: Bool
    let streamAborted: Bool
    let currency: String?
    let apiEquivalentEligibility: String?
    let tierOutcomeConfirmation: String?
    let tierOutcomeCanonical: String?
    let responseServiceTier: String?
    let fastOutcome: String?
    let confirmedServiceTier: String?
    let fastGrantEvidence: OpenCodexFastGrantEvidence
    let tokens: OpenCodexUsageTokens
    let tokenSemanticIssue: Bool
    var occurredAt: Date? = nil
}

struct OpenCodexStandardReferenceEstimator: Sendable {
    static let priceBasis = "official_standard_reference_unconfirmed_tier"
    /// Set only after a documented verification of the complete rate table.
    /// The previous UI date was not evidence of a pricing audit.
    static let auditDate: String? = nil

    func estimate(_ input: OpenCodexStandardReferenceInput) -> AILSA_SSStandardReferenceEstimate {
        let identity = OpenCodexStandardReferenceIdentityAssumption(
            provider: input.provider,
            resolvedModel: input.resolvedModel,
            requestedModel: input.requestedModel,
            modelEcho: input.modelEcho,
            usedModelFallback: false,
            confirmed: normalized(input.provider) != nil && normalized(input.resolvedModel) != nil
        )
        let baseTier = contextAssumption(
            input: input,
            fastGranted: nil,
            confirmedServiceTier: nil,
            ladder: nil,
            inputTokens: nil,
            threshold: nil
        )

        func unavailable(
            _ status: OpenCodexStandardReferenceStatus,
            leaf: String? = nil,
            context: OpenCodexStandardReferenceContextTierAssumption? = nil
        ) -> AILSA_SSStandardReferenceEstimate {
            AILSA_SSStandardReferenceEstimate(
                status: status,
                picoUSD: nil,
                priceBasis: nil,
                leaf: leaf,
                contextLadder: context?.ladder,
                estimatePartial: false,
                fastGranted: context?.fastGranted,
                confirmedServiceTier: context?.confirmedServiceTier,
                identityAssumption: identity,
                contextTierAssumption: context ?? baseTier
            )
        }

        if input.streamAborted { return unavailable(.aborted) }
        guard input.usageStatus == .reported else { return unavailable(.unreported) }
        if input.usageEstimated { return unavailable(.estimatedUsage) }
        if normalized(input.apiEquivalentEligibility) == "not_eligible_unknown_identity",
           Self.userReferenceAliases[normalized(input.resolvedModel) ?? ""] == nil {
            return unavailable(.unknownIdentity)
        }
        guard let provider = normalized(input.provider),
              let resolvedModel = normalized(input.resolvedModel)
        else {
            return unavailable(.unknownIdentity)
        }
        if let currency = normalized(input.currency), currency.uppercased() != "USD" {
            return unavailable(.nonUSD)
        }
        guard let leafID = Self.leafID(provider: provider, resolvedModel: resolvedModel),
              let leaf = Self.referenceLeaf(id: leafID, occurredAt: input.occurredAt)
        else {
            return unavailable(.unknownPrice)
        }

        // Grok 4.7's published Priority multiplier is explicitly verified. A
        // requested Fast flag alone is never enough to apply this price.
        let grokPriority = leafID == "grok-4.7"
            && input.fastGrantEvidence == .explicitlyGranted
            && ["priority", "fast"].contains(input.confirmedServiceTier ?? "")
        if input.fastGrantEvidence == .explicitlyGranted && !grokPriority {
            let context = contextAssumption(
                input: input,
                fastGranted: true,
                confirmedServiceTier: input.confirmedServiceTier,
                ladder: nil,
                inputTokens: nil,
                threshold: nil
            )
            return unavailable(.fastNotInStandardReference, leaf: leafID, context: context)
        }

        guard let inputTokens = input.tokens.inputTokens else {
            return unavailable(.unreportedTokens, leaf: leafID)
        }
        guard let outputTokens = input.tokens.outputTokens else {
            return unavailable(.unreportedTokens, leaf: leafID)
        }
        // The bridge's v1 contract does not prove cache-creation overlap.
        // Preserve unknown instead of silently charging it at ordinary input rates.
        guard !input.tokenSemanticIssue, (input.tokens.cacheCreationInputTokens ?? 0) == 0 else {
            return unavailable(.usageSemanticsConflict, leaf: leafID)
        }

        let cacheBreakdownMissing = input.tokens.cacheReadInputTokens == nil
            && input.tokens.cachedInputTokens == nil
        let cacheReadTokens = input.tokens.cacheReadInputTokens
            ?? input.tokens.cachedInputTokens
            ?? 0
        guard inputTokens >= 0,
              outputTokens >= 0,
              cacheReadTokens >= 0,
              cacheReadTokens <= inputTokens
        else {
            return unavailable(.usageSemanticsConflict, leaf: leafID)
        }

        let selected = selectContext(leaf: leaf, inputTokens: inputTokens)
        let context = contextAssumption(
            input: input,
            fastGranted: input.fastGrantEvidence.fastGranted,
            confirmedServiceTier: input.confirmedServiceTier,
            ladder: selected.ladder,
            inputTokens: inputTokens,
            threshold: leaf.threshold
        )
        guard let standardRate = selected.rate else {
            return unavailable(.overThresholdNoLongLeaf, leaf: leafID, context: context)
        }
        let rate = grokPriority ? Rate(
            inputPicoUSDPerToken: standardRate.inputPicoUSDPerToken * 2,
            cacheReadPicoUSDPerToken: standardRate.cacheReadPicoUSDPerToken * 2,
            outputPicoUSDPerToken: standardRate.outputPicoUSDPerToken * 2
        ) : standardRate
        guard let amount = Self.picoUSD(
            inputTokens: inputTokens,
            cacheReadTokens: cacheReadTokens,
            outputTokens: outputTokens,
            rate: rate
        ) else {
            return unavailable(.unknownPrice, leaf: leafID, context: context)
        }

        return AILSA_SSStandardReferenceEstimate(
            status: .referenceEstimate,
            picoUSD: amount,
            priceBasis: grokPriority
                ? (Self.userReferenceAliases[resolvedModel] == nil ? "official_priority_reference" : "user_mapped_official_priority_reference")
                : (Self.userReferenceAliases[resolvedModel] == nil ? Self.priceBasis : "user_mapped_official_standard_reference"),
            leaf: leafID,
            contextLadder: selected.ladder,
            estimatePartial: cacheBreakdownMissing,
            fastGranted: input.fastGrantEvidence.fastGranted,
            confirmedServiceTier: input.confirmedServiceTier,
            identityAssumption: identity,
            contextTierAssumption: context
        )
    }

    /// Never return a partial amount. A caller that aggregates reference
    /// estimates must retain `nil` on overflow rather than dropping a record.
    static func checkedPicoUSDSum(_ values: [Int64]) -> Int64? {
        var result: Int64 = 0
        for value in values {
            let sum = result.addingReportingOverflow(value)
            guard !sum.overflow else { return nil }
            result = sum.partialValue
        }
        return result
    }

    private struct Rate: Sendable {
        let inputPicoUSDPerToken: Int64
        let cacheReadPicoUSDPerToken: Int64
        let outputPicoUSDPerToken: Int64
    }

    private enum Threshold: Sendable {
        case allContexts
        case inputTokensGreaterThan(Int)
        case promptTokensGreaterThanOrEqual(Int)

        var kind: String {
            switch self {
            case .allContexts: "all_contexts"
            case .inputTokensGreaterThan: "input_tokens_gt"
            case .promptTokensGreaterThanOrEqual: "prompt_tokens_gte"
            }
        }

        var value: Int? {
            switch self {
            case .allContexts: nil
            case .inputTokensGreaterThan(let value), .promptTokensGreaterThanOrEqual(let value): value
            }
        }
    }

    private struct Leaf: Sendable {
        let short: Rate
        let long: Rate?
        let threshold: Threshold
    }

    /// User-approved display/reference equivalences; never used by the strict
    /// vendor-confirmed catalog or request de-duplication.
    private static let userReferenceAliases: [String: String] = [
        "kimi-for-coding": "kimi-k2.7-code", // User requested 2026-09-17: Preview uses previous ID price.
        "grok-4.7-build": "grok-4.7",
        "grok-4.6-build": "grok-4.6", "grok-4.5-build": "grok-4.5",
        "claude-fable-5-1-thinking": "claude-fable-5-1",
        "claude-fable-5.1-thinking": "claude-fable-5-1",
        "claude-fable-5.1": "claude-fable-5-1",
        "kimi-k3-max": "k3", "k3-max": "k3",
        "deepseek-v4-flash": "deepseek-flash"
    ]
    private static let crossProviderReferences: Set<String> = [
        "grok-4.7", "grok-4.6", "grok-4.5", "gemini-3.8-flash", "deepseek-flash",
        "claude-fable-5-1", "k3", "kimi-k3"
    ]
    private static func referenceLeaf(id: String, occurredAt: Date?) -> Leaf? {
        if id == "gemini-3.8-flash" {
            guard let occurredAt else { return nil }
            let fullPrice = occurredAt >= Date(timeIntervalSince1970: 1_798_761_600) // 2027-01-01 UTC
            return Leaf(short: Rate(inputPicoUSDPerToken: fullPrice ? 1_500_000 : 750_000,
                                    cacheReadPicoUSDPerToken: fullPrice ? 150_000 : 75_000,
                                    outputPicoUSDPerToken: fullPrice ? 7_500_000 : 3_750_000), long: nil, threshold: .allContexts)
        }
        if id == "deepseek-flash" {
            guard let occurredAt else { return nil }
            var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
            let day = utc.component(.weekday, from: occurredAt), hour = utc.component(.hour, from: occurredAt)
            let peak = (2...6).contains(day) && ((1..<4).contains(hour) || (6..<10).contains(hour))
            return Leaf(short: Rate(inputPicoUSDPerToken: peak ? 300_000 : 150_000,
                                    cacheReadPicoUSDPerToken: peak ? 6_000 : 3_000,
                                    outputPicoUSDPerToken: peak ? 1_200_000 : 600_000), long: nil, threshold: .allContexts)
        }
        return leaves[id]
    }

    private static let aliases: [String: String] = [
        "xai/grok-4.7": "grok-4.7",
        "cursor-proxy/grok-4.7": "grok-4.7",
        "xai/grok-4.6": "grok-4.6",
        "cursor-proxy/grok-4.6": "grok-4.6",
        "kimi-code/k3": "k3",
        "kimi-code/k3-256k": "k3",
        "kimi-code/k3[1m]": "k3",
        "kimi-code/kimi-for-coding-highspeed": "kimi-k2.7-code-highspeed",
        "kimi-code/kimi-k3": "k3",
        "openai/gpt-5.6-terra": "gpt-5.6-terra",
        "openai/gpt-5.6-sol": "gpt-5.6-sol",
        "openai/gpt-5.6-luna": "gpt-5.6-luna",
        "openai/gpt-6-astra": "gpt-6-astra",
    ]

    /// A leaf is identified by the pair, not only a coincidentally identical
    /// provider-model string. This guards against pricing an unverified proxy
    /// just because it echoes a known resolved-model name.
    private static let providersByLeaf: [String: Set<String>] = [
        "gpt-6-astra": ["openai"],
        "gpt-5.6-sol": ["openai"],
        "gpt-5.6-terra": ["openai"],
        "gpt-5.6-luna": ["openai"],
        "gpt-5.5": ["openai"],
        "gpt-5.4": ["openai"],
        "gpt-5.4-mini": ["openai"],
        "grok-4.7": ["xai", "cursor-proxy"],
        "grok-4.6": ["xai", "cursor-proxy"],
        "grok-4.5": ["xai", "cursor-proxy"],
        "k3": ["kimi-code"],
        "kimi-k3": ["kimi-code"],
        "kimi-k2.7-code": ["kimi-code", "kimi", "moonshot"],
        "kimi-k2.7-code-highspeed": ["kimi-code", "kimi", "moonshot"],
    ]

    // Amounts are USD per 1M converted to pico-USD per token. For example,
    // $2 / 1M becomes 2_000_000 pico-USD per token.
    private static let leaves: [String: Leaf] = [
        // Official K2.7 USD reference checked 2026-09-17; Preview maps here only by user instruction.
        "kimi-k2.7-code": Leaf(
            short: Rate(inputPicoUSDPerToken: 950_000, cacheReadPicoUSDPerToken: 190_000, outputPicoUSDPerToken: 4_000_000),
            long: nil, threshold: .allContexts),
        "kimi-k2.7-code-highspeed": Leaf(
            short: Rate(inputPicoUSDPerToken: 1_900_000, cacheReadPicoUSDPerToken: 380_000, outputPicoUSDPerToken: 8_000_000),
            long: nil, threshold: .allContexts),
        "claude-fable-5-1": Leaf(
            short: Rate(inputPicoUSDPerToken: 10_000_000, cacheReadPicoUSDPerToken: 250_000, outputPicoUSDPerToken: 50_000_000),
            long: nil, threshold: .allContexts),
        "gpt-6-astra": Leaf(
            short: Rate(inputPicoUSDPerToken: 10_000_000, cacheReadPicoUSDPerToken: 1_000_000, outputPicoUSDPerToken: 50_000_000),
            long: Rate(inputPicoUSDPerToken: 20_000_000, cacheReadPicoUSDPerToken: 2_000_000, outputPicoUSDPerToken: 75_000_000),
            threshold: .inputTokensGreaterThan(272_000)
        ),
        "gpt-5.6-sol": Leaf(
            short: Rate(inputPicoUSDPerToken: 4_000_000, cacheReadPicoUSDPerToken: 400_000, outputPicoUSDPerToken: 20_000_000),
            long: Rate(inputPicoUSDPerToken: 8_000_000, cacheReadPicoUSDPerToken: 800_000, outputPicoUSDPerToken: 30_000_000),
            threshold: .inputTokensGreaterThan(272_000)
        ),
        "gpt-5.6-terra": Leaf(
            short: Rate(inputPicoUSDPerToken: 2_000_000, cacheReadPicoUSDPerToken: 200_000, outputPicoUSDPerToken: 12_000_000),
            long: Rate(inputPicoUSDPerToken: 4_000_000, cacheReadPicoUSDPerToken: 400_000, outputPicoUSDPerToken: 18_000_000),
            threshold: .inputTokensGreaterThan(272_000)
        ),
        "gpt-5.6-luna": Leaf(
            short: Rate(inputPicoUSDPerToken: 200_000, cacheReadPicoUSDPerToken: 20_000, outputPicoUSDPerToken: 1_200_000),
            long: Rate(inputPicoUSDPerToken: 400_000, cacheReadPicoUSDPerToken: 40_000, outputPicoUSDPerToken: 1_800_000),
            threshold: .inputTokensGreaterThan(272_000)
        ),
        "gpt-5.5": Leaf(
            short: Rate(inputPicoUSDPerToken: 5_000_000, cacheReadPicoUSDPerToken: 500_000, outputPicoUSDPerToken: 30_000_000),
            long: Rate(inputPicoUSDPerToken: 10_000_000, cacheReadPicoUSDPerToken: 1_000_000, outputPicoUSDPerToken: 45_000_000),
            threshold: .inputTokensGreaterThan(272_000)
        ),
        "gpt-5.4": Leaf(
            short: Rate(inputPicoUSDPerToken: 2_500_000, cacheReadPicoUSDPerToken: 250_000, outputPicoUSDPerToken: 15_000_000),
            long: Rate(inputPicoUSDPerToken: 5_000_000, cacheReadPicoUSDPerToken: 500_000, outputPicoUSDPerToken: 22_500_000),
            threshold: .inputTokensGreaterThan(272_000)
        ),
        "gpt-5.4-mini": Leaf(
            short: Rate(inputPicoUSDPerToken: 750_000, cacheReadPicoUSDPerToken: 75_000, outputPicoUSDPerToken: 4_500_000),
            long: nil,
            threshold: .allContexts
        ),
        // https://docs.x.ai/developers/pricing, verified 2026-09-22.
        // The >= 200k ladder applies to all tokens, including cached input.
        "grok-4.7": Leaf(
            short: Rate(inputPicoUSDPerToken: 2_000_000, cacheReadPicoUSDPerToken: 500_000, outputPicoUSDPerToken: 6_000_000),
            long: Rate(inputPicoUSDPerToken: 4_000_000, cacheReadPicoUSDPerToken: 1_000_000, outputPicoUSDPerToken: 12_000_000),
            threshold: .promptTokensGreaterThanOrEqual(200_000)
        ),
        "grok-4.6": Leaf(
            short: Rate(inputPicoUSDPerToken: 2_000_000, cacheReadPicoUSDPerToken: 500_000, outputPicoUSDPerToken: 6_000_000),
            long: Rate(inputPicoUSDPerToken: 4_000_000, cacheReadPicoUSDPerToken: 1_000_000, outputPicoUSDPerToken: 12_000_000),
            threshold: .promptTokensGreaterThanOrEqual(200_000)
        ),
        "grok-4.5": Leaf(
            short: Rate(inputPicoUSDPerToken: 2_000_000, cacheReadPicoUSDPerToken: 300_000, outputPicoUSDPerToken: 6_000_000),
            long: Rate(inputPicoUSDPerToken: 4_000_000, cacheReadPicoUSDPerToken: 600_000, outputPicoUSDPerToken: 12_000_000),
            threshold: .promptTokensGreaterThanOrEqual(200_000)
        ),
        "k3": Leaf(
            short: Rate(inputPicoUSDPerToken: 3_000_000, cacheReadPicoUSDPerToken: 300_000, outputPicoUSDPerToken: 15_000_000),
            long: nil,
            threshold: .allContexts
        ),
        "kimi-k3": Leaf(
            short: Rate(inputPicoUSDPerToken: 3_000_000, cacheReadPicoUSDPerToken: 300_000, outputPicoUSDPerToken: 15_000_000),
            long: nil,
            threshold: .allContexts
        ),
    ]

    private func contextAssumption(
        input: OpenCodexStandardReferenceInput,
        fastGranted: Bool?,
        confirmedServiceTier: String?,
        ladder: String?,
        inputTokens: Int?,
        threshold: Threshold?
    ) -> OpenCodexStandardReferenceContextTierAssumption {
        OpenCodexStandardReferenceContextTierAssumption(
            confirmation: input.tierOutcomeConfirmation,
            responseServiceTier: input.responseServiceTier,
            fastOutcome: input.fastOutcome,
            fastGranted: fastGranted,
            confirmedServiceTier: confirmedServiceTier,
            ladder: ladder,
            inputTokens: inputTokens,
            thresholdKind: threshold?.kind,
            thresholdValue: threshold?.value,
            silentShortApplied: false
        )
    }

    private static func leafID(provider: String, resolvedModel: String) -> String? {
        if let alias = userReferenceAliases[resolvedModel] { return alias }
        if crossProviderReferences.contains(resolvedModel) { return resolvedModel }
        if let alias = aliases["\(provider)/\(resolvedModel)"] { return alias }
        guard leaves[resolvedModel] != nil,
              providersByLeaf[resolvedModel]?.contains(provider) == true
        else {
            return nil
        }
        return resolvedModel
    }

    private func selectContext(leaf: Leaf, inputTokens: Int) -> (rate: Rate?, ladder: String) {
        switch leaf.threshold {
        case .allContexts:
            return (leaf.short, "standard-all-contexts")
        case .inputTokensGreaterThan(let threshold):
            return inputTokens > threshold
                ? (leaf.long, "standard-long")
                : (leaf.short, "standard-short")
        case .promptTokensGreaterThanOrEqual(let threshold):
            return inputTokens >= threshold
                ? (leaf.long, "standard-long")
                : (leaf.short, "standard-short")
        }
    }

    private static func picoUSD(
        inputTokens: Int,
        cacheReadTokens: Int,
        outputTokens: Int,
        rate: Rate
    ) -> Int64? {
        guard let uncachedInput = Int64(exactly: inputTokens - cacheReadTokens),
              let cachedInput = Int64(exactly: cacheReadTokens),
              let output = Int64(exactly: outputTokens),
              uncachedInput >= 0,
              cachedInput >= 0,
              output >= 0
        else {
            return nil
        }
        func product(_ tokens: Int64, _ unit: Int64) -> Int64? {
            let result = tokens.multipliedReportingOverflow(by: unit)
            return result.overflow ? nil : result.partialValue
        }
        func sum(_ lhs: Int64, _ rhs: Int64) -> Int64? {
            let result = lhs.addingReportingOverflow(rhs)
            return result.overflow ? nil : result.partialValue
        }
        guard let uncached = product(uncachedInput, rate.inputPicoUSDPerToken),
              let cached = product(cachedInput, rate.cacheReadPicoUSDPerToken),
              let outputCost = product(output, rate.outputPicoUSDPerToken),
              let inputCost = sum(uncached, cached)
        else {
            return nil
        }
        return sum(inputCost, outputCost)
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

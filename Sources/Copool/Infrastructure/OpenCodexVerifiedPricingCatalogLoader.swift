import Foundation
import CoreFoundation

/// Fails closed when the audited runtime-pricing artifact cannot prove an
/// exact provider/model/tier/context binding. This loader deliberately
/// accepts no aliases, platform variants, time-window rules, or inferred
/// service tiers.
enum OpenCodexVerifiedPricingCatalogLoader {
    static let expectedSchema = "ailsa.ass.opencodex-runtime-pricing-bindings.v1"

    enum LoadError: Error, Equatable {
        case unreadable
        case malformedRoot
        case unsupportedSchema
        case malformedProvenance
        case noEligibleBindings
        case ambiguousBinding
    }

    static func load(url: URL) throws -> OpenCodexPricingCatalog {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
            throw LoadError.unreadable
        }
        return try decode(data: data, sourceURL: url)
    }

    static func decode(data: Data, sourceURL: URL) throws -> OpenCodexPricingCatalog {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LoadError.malformedRoot
        }
        guard nonempty(root["schema"]) == expectedSchema else {
            throw LoadError.unsupportedSchema
        }
        guard let generatedAt = nonempty(root["generatedAt"]),
              let auditDate = nonempty(root["auditDate"]),
              let sourceAuditSchemaVersion = nonnegativeInt(root["sourceAuditSchemaVersion"]),
              sourceAuditSchemaVersion == 1,
              isISO8601(generatedAt),
              isISODate(auditDate),
              let entries = root["entries"] as? [[String: Any]]
        else {
            throw LoadError.malformedProvenance
        }

        var acceptedBindings: [OpenCodexPricingCatalog.Binding] = []
        for entry in entries {
            acceptedBindings.append(contentsOf: bindings(from: entry, auditDate: auditDate))
        }
        guard !acceptedBindings.isEmpty else { throw LoadError.noEligibleBindings }
        let canonicalized = try canonicalizeExactDuplicates(acceptedBindings)

        return OpenCodexPricingCatalog(
            schema: expectedSchema,
            catalogVersion: "v1|audit=\(auditDate)|generated=\(generatedAt)",
            provenance: .init(
                artifactPath: sourceURL.path,
                generatedAt: generatedAt,
                auditDate: auditDate,
                sourceAuditSchemaVersion: sourceAuditSchemaVersion,
                acceptedBindingCount: canonicalized.bindings.count,
                equivalentDuplicateBindingCount: canonicalized.equivalentDuplicatesCollapsed
            ),
            bindings: canonicalized.bindings
        )
    }

    /// The audit artifact can contain a repeated upstream observation through
    /// both a combo row and its direct row. This only coalesces it if the exact
    /// provider/model/tier/context *and every retained price/source field* are
    /// identical. Any real disagreement remains a fail-closed ambiguity.
    private static func canonicalizeExactDuplicates(
        _ candidates: [OpenCodexPricingCatalog.Binding]
    ) throws -> (bindings: [OpenCodexPricingCatalog.Binding], equivalentDuplicatesCollapsed: Int) {
        let groups = Dictionary(grouping: candidates, by: exactBindingKey)
        var canonical: [OpenCodexPricingCatalog.Binding] = []
        var collapsed = 0
        for key in groups.keys.sorted() {
            guard let group = groups[key] else { continue }
            let ordered = group.sorted { $0.bindingID < $1.bindingID }
            guard let representative = ordered.first else { continue }
            guard ordered.dropFirst().allSatisfy({ equivalentQuote($0, representative) }) else {
                throw LoadError.ambiguousBinding
            }
            let sourceBindingIDs = Array(
                Set(ordered.flatMap(\.sourceBindingIDs))
            ).sorted()
            canonical.append(
                OpenCodexPricingCatalog.Binding(
                    bindingID: representative.bindingID,
                    sourceBindingIDs: sourceBindingIDs,
                    provider: representative.provider,
                    resolvedModel: representative.resolvedModel,
                    serviceTier: representative.serviceTier,
                    inputTokenCondition: representative.inputTokenCondition,
                    status: representative.status,
                    currency: representative.currency,
                    inputPicoUSDPerToken: representative.inputPicoUSDPerToken,
                    cachedInputPicoUSDPerToken: representative.cachedInputPicoUSDPerToken,
                    outputPicoUSDPerToken: representative.outputPicoUSDPerToken,
                    cacheInputHandling: representative.cacheInputHandling,
                    reasoningOutputIsSubset: representative.reasoningOutputIsSubset,
                    officialSourceURL: representative.officialSourceURL
                )
            )
            collapsed += ordered.count - 1
        }
        return (canonical, collapsed)
    }

    private static func exactBindingKey(_ binding: OpenCodexPricingCatalog.Binding) -> String {
        [
            binding.provider,
            binding.resolvedModel,
            binding.serviceTier ?? "(none)",
            inputTokenConditionKey(binding.inputTokenCondition),
        ].joined(separator: "\u{1F}")
    }

    private static func inputTokenConditionKey(_ condition: OpenCodexPricingInputTokenCondition) -> String {
        switch condition {
        case .allContexts: "all_contexts"
        case .inputTokensLessThanOrEqual(let value): "input_tokens_lte=\(value)"
        case .inputTokensGreaterThan(let value): "input_tokens_gt=\(value)"
        case .promptTokensLessThan(let value): "prompt_tokens_lt=\(value)"
        case .promptTokensGreaterThanOrEqual(let value): "prompt_tokens_gte=\(value)"
        }
    }

    private static func equivalentQuote(
        _ lhs: OpenCodexPricingCatalog.Binding,
        _ rhs: OpenCodexPricingCatalog.Binding
    ) -> Bool {
        lhs.provider == rhs.provider
            && lhs.resolvedModel == rhs.resolvedModel
            && lhs.serviceTier == rhs.serviceTier
            && lhs.inputTokenCondition == rhs.inputTokenCondition
            && lhs.status == rhs.status
            && lhs.currency == rhs.currency
            && lhs.inputPicoUSDPerToken == rhs.inputPicoUSDPerToken
            && lhs.cachedInputPicoUSDPerToken == rhs.cachedInputPicoUSDPerToken
            && lhs.outputPicoUSDPerToken == rhs.outputPicoUSDPerToken
            && lhs.cacheInputHandling == rhs.cacheInputHandling
            && lhs.reasoningOutputIsSubset == rhs.reasoningOutputIsSubset
            && lhs.officialSourceURL == rhs.officialSourceURL
    }

    private static func bindings(
        from entry: [String: Any],
        auditDate: String
    ) -> [OpenCodexPricingCatalog.Binding] {
        guard nonempty(entry["status"]) == "conditional",
              nonempty(entry["apiEquivalentEligibility"]) == "conditional_on_reported_identity_and_actual_tier",
              nonempty(entry["identityStatus"])?.hasPrefix("exact public model id;") == true,
              let bindingID = nonempty(entry["bindingId"]),
              let provider = nonempty(entry["provider"]),
              let resolvedModel = nonempty(entry["resolvedModel"]),
              let rules = entry["rateRules"] as? [[String: Any]]
        else {
            return []
        }

        return rules.flatMap { rule in
            bindings(
                from: rule,
                bindingID: bindingID,
                provider: provider,
                resolvedModel: resolvedModel,
                auditDate: auditDate
            )
        }
    }

    private static func bindings(
        from rule: [String: Any],
        bindingID: String,
        provider: String,
        resolvedModel: String,
        auditDate: String
    ) -> [OpenCodexPricingCatalog.Binding] {
        guard let ruleID = nonempty(rule["id"]),
              let condition = rule["condition"] as? [String: Any],
              let context = parseContext(condition),
              let inputRate = picoUSDPerToken(rule["inputUSDPerMillionTokens"]),
              let cacheRate = picoUSDPerToken(rule["cacheReadUSDPerMillionTokens"]),
              let outputRate = picoUSDPerToken(rule["outputUSDPerMillionTokens"]),
              let officialSourceURL = verifiedOfficialSourceURL(rule["source"], auditDate: auditDate)
        else {
            return []
        }
        let requirements = stringSet(rule["requirements"])
        guard requirements.isSuperset(of: [
            "confirmed_vendor_service_tier",
            "confirmed_fast_grant_consistency",
            "reported_request_input_tokens",
        ]) else { return [] }

        let normalizedRuleID = ruleID.lowercased()
        let isStandard = normalizedRuleID == "standard" || normalizedRuleID.hasPrefix("standard-")
        let isFast = normalizedRuleID == "fast" || normalizedRuleID.hasPrefix("fast-") || normalizedRuleID == "priority"
        guard isStandard || isFast else { return [] }

        let explicitTiers = stringList(condition["confirmed_service_tier"]).map { $0.lowercased() }
        let tiers: [String]
        if isStandard {
            // The audited rule name is the only permitted mapping for a
            // standard rule that omits an explicit tier list.
            guard explicitTiers.isEmpty || explicitTiers == ["standard"] else { return [] }
            tiers = ["standard"]
        } else {
            guard !explicitTiers.isEmpty,
                  Set(explicitTiers).isSubset(of: ["fast", "priority"])
            else { return [] }
            tiers = explicitTiers
        }

        return tiers.map { tier in
            OpenCodexPricingCatalog.Binding(
                bindingID: "\(bindingID):\(ruleID):\(tier)",
                provider: provider,
                resolvedModel: resolvedModel,
                serviceTier: tier,
                inputTokenCondition: context,
                status: .verified,
                currency: "USD",
                inputPicoUSDPerToken: inputRate,
                cachedInputPicoUSDPerToken: cacheRate,
                outputPicoUSDPerToken: outputRate,
                cacheInputHandling: .cachedSubsetDiscounted,
                reasoningOutputIsSubset: true,
                officialSourceURL: officialSourceURL
            )
        }
    }

    private static func parseContext(_ condition: [String: Any]) -> OpenCodexPricingInputTokenCondition? {
        let allowed = Set([
            "all_contexts", "input_tokens_lte", "input_tokens_gt",
            "prompt_tokens_lt", "prompt_tokens_gte", "confirmed_service_tier",
        ])
        guard Set(condition.keys).isSubset(of: allowed) else { return nil }
        let contextKeys = [
            "all_contexts", "input_tokens_lte", "input_tokens_gt",
            "prompt_tokens_lt", "prompt_tokens_gte",
        ].filter { condition[$0] != nil }
        guard contextKeys.count == 1, let key = contextKeys.first else { return nil }
        switch key {
        case "all_contexts":
            return (condition[key] as? Bool) == true ? .allContexts : nil
        case "input_tokens_lte":
            return nonnegativeInt(condition[key]).map(OpenCodexPricingInputTokenCondition.inputTokensLessThanOrEqual)
        case "input_tokens_gt":
            return nonnegativeInt(condition[key]).map(OpenCodexPricingInputTokenCondition.inputTokensGreaterThan)
        case "prompt_tokens_lt":
            return nonnegativeInt(condition[key]).map(OpenCodexPricingInputTokenCondition.promptTokensLessThan)
        case "prompt_tokens_gte":
            return nonnegativeInt(condition[key]).map(OpenCodexPricingInputTokenCondition.promptTokensGreaterThanOrEqual)
        default:
            return nil
        }
    }

    private static func verifiedOfficialSourceURL(_ value: Any?, auditDate: String) -> String? {
        guard let sources = value as? [[String: Any]] else { return nil }
        return sources.compactMap { source in
            guard nonempty(source["verifiedOn"]) == auditDate,
                  let url = nonempty(source["url"]),
                  let parsed = URL(string: url),
                  parsed.scheme == "https"
            else { return nil }
            return url
        }.first
    }

    private static func picoUSDPerToken(_ value: Any?) -> Int64? {
        guard let text = nonempty(value) else { return nil }
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count <= 2,
              let whole = Int64(pieces[0]),
              whole >= 0,
              pieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) })
        else { return nil }
        let fraction = pieces.count == 2 ? String(pieces[1]) : ""
        guard fraction.count <= 6 else { return nil }
        let padded = fraction.padding(toLength: 6, withPad: "0", startingAt: 0)
        guard let fractional = Int64(padded) else { return nil }
        let product = whole.multipliedReportingOverflow(by: 1_000_000)
        guard !product.overflow else { return nil }
        let sum = product.partialValue.addingReportingOverflow(fractional)
        return sum.overflow ? nil : sum.partialValue
    }

    private static func stringSet(_ value: Any?) -> Set<String> {
        Set(stringList(value))
    }

    private static func stringList(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap(nonempty)
    }

    private static func nonempty(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func nonnegativeInt(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let decimal = number.doubleValue
        guard decimal.isFinite, decimal >= 0, decimal.rounded(.towardZero) == decimal, decimal <= Double(Int.max) else { return nil }
        return Int(decimal)
    }

    private static func isISO8601(_ value: String) -> Bool {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if fractional.date(from: value) != nil { return true }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value) != nil
    }

    private static func isISODate(_ value: String) -> Bool {
        value.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) != nil
    }
}

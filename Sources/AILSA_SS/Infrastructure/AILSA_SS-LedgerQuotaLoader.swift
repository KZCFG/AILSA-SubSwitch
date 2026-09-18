import Foundation

/// Thin local-file boundary for the OpenCodex ledger.  It owns no router,
/// account, session body, or network access.  `LocalQuotaManagementUsageService`
/// uses this as its ledger-primary branch and keeps its native Codex-session
/// path as an exclusive fallback.
struct AILSA_SSLedgerQuotaLoader: Sendable {
    let ledgerURL: URL
    let reader: AILSA_SSLedgerMeteringReader
    let strictCatalogProvenance: OpenCodexPricingCatalog.Provenance?

    init(
        ledgerURL: URL,
        pricingCatalog: OpenCodexPricingCatalog = .empty
    ) {
        self.ledgerURL = ledgerURL
        reader = AILSA_SSLedgerMeteringReader(pricingCatalog: pricingCatalog)
        strictCatalogProvenance = pricingCatalog.provenance
    }

    /// Production path: a failed or absent verified catalog leaves strict
    /// pricing unavailable while preserving ledger metering and the separate
    /// standard-reference branch. It never falls back to aliases or a broad
    /// models.dev cache.
    init(
        ledgerURL: URL,
        verifiedPricingCatalogURL: URL?
    ) {
        self.ledgerURL = ledgerURL
        let catalog = verifiedPricingCatalogURL.flatMap {
            try? AILSA_SSVerifiedPricingCatalogLoader.load(url: $0)
        } ?? .empty
        reader = AILSA_SSLedgerMeteringReader(pricingCatalog: catalog)
        strictCatalogProvenance = catalog.provenance
    }

    func load() throws -> OpenCodexLedgerAnalytics {
        let data = try Data(contentsOf: ledgerURL, options: [.mappedIfSafe])
        // The reader takes its default `scannedAt` after parsing completes.
        return reader.read(data: data)
    }
}

/// Actor-confined incremental local ledger reader. No raw JSON is retained.
/// Replacement/truncation/changed committed boundary invalidates the cache.
struct OpenCodexIncrementalLedger: Sendable {
    private var state = AILSA_SSLedgerMeteringReader.State()
    private var offset: UInt64 = 0
    private var identity: String?
    private var boundary = Data()
    private var reader: AILSA_SSLedgerMeteringReader?
    private var catalogStamp: Date?
    private(set) var bytesRead: UInt64 = 0

    private var compactMode = false
    private var contributions: [String: QuotaContribution] = [:]
    mutating func load(url: URL, catalogURL: URL?) throws -> OpenCodexLedgerAnalytics {
        try readFile(url: url, catalogURL: catalogURL, compact: false)
        return reader!.result(state: state)
    }
    mutating func snapshot(url: URL, catalogURL: URL?, now: Date) throws -> QuotaDashboardSnapshot {
        try readFile(url: url, catalogURL: catalogURL, compact: true)
        return QuotaDashboardSnapshot.compact(contributions.values, discarded: state.duplicateRowsDiscarded, now: now, pricingProvenance: reader?.pricingProvenance ?? [])
    }
    private mutating func readFile(url: URL, catalogURL: URL?, compact: Bool) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let currentID = "\(attrs[.systemNumber] ?? 0):\(attrs[.systemFileNumber] ?? 0):\(TimeZone.current.identifier)"
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        let stamp = catalogURL.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        var changed = compactMode != compact || identity != currentID || size < offset || stamp != catalogStamp
        if !changed && offset > 0 {
            try handle.seek(toOffset: offset - UInt64(boundary.count))
            changed = try handle.read(upToCount: boundary.count) != boundary
        }
        if changed || reader == nil {
            state = .init(); contributions = [:]; compactMode = compact; offset = 0; boundary = Data(); identity = currentID; catalogStamp = stamp
            let catalog = catalogURL.flatMap { try? AILSA_SSVerifiedPricingCatalogLoader.load(url: $0) } ?? .empty
            reader = AILSA_SSLedgerMeteringReader(pricingCatalog: catalog)
        }
        try handle.seek(toOffset: offset)
        var pending = Data()
        var position = offset
        bytesRead = 0
        while position < size {
            try Task.checkCancellation()
            guard let chunk = try handle.read(upToCount: Int(min(262_144, size - position))), !chunk.isEmpty else { break }
            position += UInt64(chunk.count); bytesRead += UInt64(chunk.count)
            pending.append(chunk)
            if let newline = pending.lastIndex(of: 10) {
                let complete = Data(pending[...newline])
                reader!.append(data: complete, to: &state)
                if compact {
                    for (id, record) in reader!.drainChangedRecords(&state) {
                        contributions[id] = QuotaDashboardSnapshot.contribution(record)
                    }
                }
                offset += UInt64(complete.count)
                boundary = Data((boundary + complete).suffix(256))
                pending = Data(pending[pending.index(after: newline)...])
            }
        }
        // Unterminated tail is retried from offset on the next refresh.
    }
}

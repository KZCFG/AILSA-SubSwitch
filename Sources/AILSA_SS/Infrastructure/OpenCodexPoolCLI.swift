import Foundation

/// A local-only handoff surface for maintenance agents. Never prints credentials or emails.
enum OpenCodexPoolCLI {
    static func run(_ command: String) async -> Int32 {
        do {
            let service = OpenCodexPoolService()
            switch command {
            case "takeover": try await service.setManagementEnabled(true)
            case "stop": try await service.setManagementEnabled(false)
            case "check": try await service.runManagedCycle()
            case "verify": try await service.verifyRuntime()
            case "status", "diagnose": break
            default: throw AppError.invalidData("Expected status, verify, takeover, check, stop, or diagnose.")
            }
            let pool = try await service.snapshot()
            var output: [String: Any] = ["provider": pool.provider, "managementEnabled": pool.managementEnabled,
                "legacyConflict": pool.legacyConflict, "rangeSwitchingEnabled": pool.enabled,
                "accounts": pool.accounts.count, "selected": pool.accounts.filter(\.selected).count,
                "freshQuotaAccounts": pool.accounts.filter { $0.remainingPercent != nil }.count,
                "currentFound": pool.accounts.contains { $0.id == pool.activeAccountId }]
            if command == "diagnose" {
                output["monitoredFamily"] = pool.monitoredFamily
                output["decisionHistory"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(OpenCodexPoolAudit.read(at: service.auditURL)))
            }
            print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), encoding: .utf8)!)
            return 0
        } catch {
            // The controlled errors contain only product messages, never subprocess diagnostics.
            print("{\"error\":\"pool_control_failed\"}")
            return 1
        }
    }
}

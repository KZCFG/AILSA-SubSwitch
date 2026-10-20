import SwiftUI

struct SettingsQuotaPoolSection: View {
    @ObservedObject var model: SettingsPageModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack {
                Text(L10n.tr("settings.pool.title")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(L10n.tr("settings.pool.refresh")) { Task { await model.refreshOpenCodexPool() } }
                    .disabled(model.poolBusy)
            }
            if let pool = model.openCodexPool {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L10n.tr(pool.legacyConflict ? "settings.pool.control_external" : (pool.managementEnabled ? "settings.pool.control_owned" : "settings.pool.control_idle")))
                            .font(.system(size: 13, weight: .medium))
                        if let stamp = pool.lastSyncAt {
                            Text(L10n.tr("settings.pool.last_sync") + " " + Date(timeIntervalSince1970: stamp).formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button(L10n.tr(pool.managementEnabled && !pool.legacyConflict ? "settings.pool.control_stop" : "settings.pool.control_takeover")) {
                        model.mutateOpenCodexPool { try await $0.setManagementEnabled(!pool.managementEnabled || pool.legacyConflict) }
                    }
                }
                if let decision = pool.lastDecision { SettingsPoolDecisionView(decision: decision, accounts: pool.accounts) }
                Text(L10n.tr("settings.pool.inflight_note")).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(L10n.tr("settings.pool.control_detail")).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(L10n.tr("settings.pool.follow_desktop"), isOn: Binding(
                    get: { model.settings.syncOpencodeAntigravityAuth },
                    set: { model.setSyncOpencodeAntigravityAuth($0) }))
                    .toggleStyle(SettingsNeutralSwitchStyle()).disabled(!pool.managementEnabled || pool.legacyConflict)

                Toggle(L10n.tr("settings.pool.enabled"), isOn: Binding(get: { pool.enabled }, set: { enabled in
                    model.mutateOpenCodexPool { try await $0.setEnabled(enabled) }
                }))
                .toggleStyle(SettingsNeutralSwitchStyle()).disabled(!pool.managementEnabled || pool.legacyConflict)
                ForEach(pool.accounts) { account in
                    SettingsQuotaPoolAccountRow(account: account, active: pool.activeAccountId == account.id, enabled: pool.enabled, managed: pool.managementEnabled && !pool.legacyConflict, family: pool.monitoredFamily, model: model)
                }
                ForEach(pool.candidates) { candidate in
                    HStack {
                        Text(candidate.label).font(.system(size: 13))
                        Spacer()
                        Button(L10n.tr("settings.pool.import_saved")) { model.mutateOpenCodexPool { try await $0.importSavedAccount(id: candidate.id) } }
                    }.disabled(!pool.managementEnabled || pool.legacyConflict)
                }
                Text(L10n.tr("settings.pool.detail"))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text(L10n.tr("settings.pool.unavailable"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let message = model.poolMessage, model.openCodexPool != nil { Text(message).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .disabled(model.poolBusy)
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                await model.refreshOpenCodexPool(forceRefresh: false)
            }
        }
    }
}

private struct SettingsPoolDecisionView: View {
    let decision: OpenCodexPoolDecision
    let accounts: [OpenCodexPoolAccount]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.tr("settings.pool.decision_time") + " " + Date(timeIntervalSince1970: decision.timestamp).formatted(date: .omitted, time: .standard))
                .foregroundStyle(.secondary)
            Text(L10n.tr(decision.outcome.titleKey))
            if let id = decision.activeAccountId, let account = accounts.first(where: { $0.id == id }), let family = decision.family {
                Text(L10n.tr("settings.pool.decision_metrics", account.label, family == "claude" ? "Claude" : "Gemini",
                    decision.remainingPercent.map { String(format: "%.2f%%", $0) } ?? "—",
                    decision.threshold.map { "\($0)%" } ?? "—")).foregroundStyle(.secondary)
            }
            if let stage = decision.stage {
                let stageKey = "settings.pool.stage." + stage
                Text(L10n.tr(stageKey)).foregroundStyle(.secondary)
            }
            if decision.credentialSyncDeferred { Text(L10n.tr("settings.pool.sync_deferred")).foregroundStyle(.secondary) }
        }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
    }
}

private struct SettingsQuotaPoolAccountRow: View {
    let account: OpenCodexPoolAccount
    let active: Bool
    let enabled: Bool
    let managed: Bool
    let family: String
    @ObservedObject var model: SettingsPageModel
    @State private var minimum = 10
    @State private var maximum = 10
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(isOn: Binding(get: { account.selected }, set: { selected in
                model.mutateOpenCodexPool { try await $0.setSelected(id: account.id, selected: selected) }
            })) {
                Text(account.label + (active ? " · " + L10n.tr("settings.pool.current") : ""))
                    .font(.system(size: 13, weight: .medium)).lineLimit(1)
            }.toggleStyle(.checkbox).disabled(!managed)
            if !active {
                Button(L10n.tr("settings.pool.use_account")) { model.mutateOpenCodexPool { try await $0.selectAccount(id: account.id) } }
                    .font(.system(size: 11)).disabled(!managed || !account.selected || !account.isAvailable || account.needsReauth)
            }
            HStack(spacing: 6) {
                Text(L10n.tr("settings.pool.remaining"))
                TextField("5", value: $minimum, formatter: NumberFormatter()).frame(width: 38)
                Text("% –")
                TextField("10", value: $maximum, formatter: NumberFormatter()).frame(width: 38)
                Text("%")
                Button(L10n.tr("settings.pool.save")) {
                    let range = OpenCodexPoolRange(minimum: minimum, maximum: maximum)
                    model.mutateOpenCodexPool { try await $0.setRange(id: account.id, range: range) }
                }.disabled(minimum < 0 || maximum > 99 || minimum > maximum)
                Spacer()
                Text(account.effectiveThreshold.map { L10n.tr("settings.pool.current_threshold", $0) } ?? L10n.tr(enabled ? "settings.pool.threshold_pending" : "settings.pool.disabled"))
                    .foregroundStyle(.secondary)
            }.font(.system(size: 11))
            if let remaining = account.remainingPercent {
                Text(L10n.tr("settings.pool.precise_remaining", family == "claude" ? "Claude" : "Gemini", String(format: "%.2f%%", remaining)))
                    .help(L10n.tr("settings.pool.precise_remaining_help"))
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if let threshold = account.effectiveClaudeThreshold {
                Text(L10n.tr("settings.pool.claude_threshold", threshold)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if !account.isAvailable && !account.needsReauth { Text(L10n.tr("settings.pool.unavailable_account")).font(.system(size: 11)).foregroundStyle(.secondary) }
            if account.needsReauth { Text(L10n.tr("settings.pool.sign_in_required")).font(.system(size: 11)).foregroundStyle(.secondary) }
        }
        .onAppear { minimum = account.range.minimum; maximum = account.range.maximum }
        .onChange(of: account.range) { _, value in minimum = value.minimum; maximum = value.maximum }
    }
}

struct SettingsAccountPoolSection: View {
    @ObservedObject var model: SettingsPageModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(L10n.tr("settings.quota_probe.title"), selection: Binding(
                get: { model.settings.antigravityQuotaActivationMode },
                set: { model.updateAntigravityQuotaActivationMode($0) }
            )) {
                ForEach(QuotaRequestActivationMode.allCases.filter { $0 != .poolAccounts || model.openCodexPool != nil || model.settings.antigravityQuotaActivationMode == .poolAccounts }, id: \.self) { mode in
                    Text(L10n.tr(mode.titleKey)).tag(mode)
                }
            }
            .pickerStyle(.menu)
            .font(.system(size: 13, weight: .medium))
            Text(L10n.tr("settings.quota_probe.detail"))
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.settings.antigravityQuotaActivationMode != .off {
                HStack(spacing: 12) {
                    Text(L10n.tr("settings.quota_activation.hours"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settings.quotaWindowActivationStartHour },
                            set: { model.updateQuotaWindowActivationStartHour($0) }
                        )
                    ) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    Text("–")
                    Picker(
                        "",
                        selection: Binding(
                            get: { model.settings.quotaWindowActivationEndHour },
                            set: { model.updateQuotaWindowActivationEndHour($0) }
                        )
                    ) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(String(format: "%02d:00", hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            SettingsQuotaPoolSection(model: model)
        }
        .padding(.bottom, 16)
    }
}

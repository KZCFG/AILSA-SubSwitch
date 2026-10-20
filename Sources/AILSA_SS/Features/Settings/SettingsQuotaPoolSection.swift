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
                Toggle(L10n.tr("settings.pool.enabled"), isOn: Binding(get: { pool.enabled }, set: { enabled in
                    model.mutateOpenCodexPool { try await $0.setEnabled(enabled) }
                }))
                .toggleStyle(SettingsNeutralSwitchStyle())
                ForEach(pool.accounts) { account in
                    SettingsQuotaPoolAccountRow(account: account, active: pool.activeAccountId == account.id, enabled: pool.enabled, model: model)
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
    }
}

private struct SettingsQuotaPoolAccountRow: View {
    let account: OpenCodexPoolAccount
    let active: Bool
    let enabled: Bool
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
            }.toggleStyle(.checkbox)
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

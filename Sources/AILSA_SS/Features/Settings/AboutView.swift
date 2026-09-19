import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AboutView: View {
    @Environment(\.panelViewportSize) private var viewport
    private var compact: Bool { (viewport?.height ?? 760) < 700 }
    @State private var isBackupWarningPresented = false
    @State private var isDeleteWarningPresented = false
    @State private var operationMessage: String?
    @State private var operationFailed = false

    var body: some View {
        VStack(spacing: 18) {
            productInfo
                .frame(maxWidth: .infinity)
                .padding(compact ? 18 : 28)
                .cardSurface(cornerRadius: LayoutRules.cardRadius)

            HStack(spacing: 8) {
                projectLink("GitHub", icon: "chevron.left.forwardslash.chevron.right", path: "")
                projectLink(L10n.tr("about.licenses"), icon: "doc.text", path: "/blob/main/Sources/AILSA_SS/Resources/THIRD_PARTY_NOTICES.md")
            }

            configurationActions

            if let operationMessage {
                Text(operationMessage)
                    .font(.caption)
                    .foregroundStyle(operationFailed ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("© 2026 KZCFG · MIT")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .alert(
            L10n.tr("about.configuration.backup.title"),
            isPresented: $isBackupWarningPresented
        ) {
            Button(L10n.tr("about.configuration.backup.confirm")) {
                chooseBackupDestination()
            }
            Button(L10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("about.configuration.backup.warning"))
        }
        .alert(
            L10n.tr("about.configuration.delete.title"),
            isPresented: $isDeleteWarningPresented
        ) {
            Button(L10n.tr("about.configuration.delete.confirm"), role: .destructive) {
                deleteLocalConfiguration()
            }
            Button(L10n.tr("common.cancel"), role: .cancel) {}
        } message: {
            Text(L10n.tr("about.configuration.delete.warning"))
        }
    }

    private var configurationActions: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive")
                .foregroundStyle(.secondary)
            Text(L10n.tr("about.configuration.title"))
                .font(.callout.weight(.medium))
            Spacer(minLength: 8)
            Button(L10n.tr("about.configuration.backup")) {
                operationMessage = nil
                isBackupWarningPresented = true
            }
            .buttonStyle(.bordered)
            Text("/")
                .foregroundStyle(.secondary)
            Button(L10n.tr("about.configuration.delete")) {
                operationMessage = nil
                isDeleteWarningPresented = true
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .cardSurface(cornerRadius: 10)
    }

    private var productInfo: some View {
        VStack(spacing: 10) {
            if let url = Bundle.main.url(forResource: "AILSASubSwitch", withExtension: "icns"),
               let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().frame(width: compact ? 80 : 112, height: compact ? 80 : 112)
                    .accessibilityHidden(true)
                    .padding(.bottom, 8)
            }
            Text("AILSA SubSwitch").font(.system(size: 24, weight: .bold))
            Text(String(format: L10n.tr("about.version_format"), AppVersion.marketing))
                .font(.system(size: 16)).foregroundStyle(.secondary)
            Text(String(format: L10n.tr("about.built_format"), AppVersion.buildDate))
                .font(.system(size: 12)).foregroundStyle(.secondary)
            Text(L10n.tr("about.tagline"))
                .font(.system(size: 14)).padding(.top, 2)
                .multilineTextAlignment(.center)
        }
    }

    private func projectLink(_ title: String, icon: String, path: String) -> some View {
        externalLink(title, icon: icon, url: "https://github.com/KZCFG/AILSA-SubSwitch" + path)
    }

    private func externalLink(_ title: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(title, systemImage: icon)
                .font(.callout)
                .lineLimit(1).minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, minHeight: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardSurface(cornerRadius: 8)
    }

    private func chooseBackupDestination() {
        #if os(macOS)
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "AILSA-SubSwitch-configuration.json"
        panel.title = L10n.tr("about.configuration.backup")
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try LocalConfigurationManager.live().writeBackup(to: url)
            operationFailed = false
            operationMessage = L10n.tr("about.configuration.backup.saved")
        } catch {
            operationFailed = true
            operationMessage = String(format: L10n.tr("about.configuration.operation_failed_format"), error.localizedDescription)
        }
        #endif
    }

    private func deleteLocalConfiguration() {
        do {
            try LocalConfigurationManager.live().deleteLocalConfiguration()
            operationFailed = false
            operationMessage = L10n.tr("about.configuration.delete.deleted")
            #if os(macOS)
            // Terminating here prevents in-memory account state from surviving
            // a factory reset. The next launch starts with empty defaults.
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            #endif
        } catch {
            operationFailed = true
            operationMessage = String(format: L10n.tr("about.configuration.operation_failed_format"), error.localizedDescription)
        }
    }
}

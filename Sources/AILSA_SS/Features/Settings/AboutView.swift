import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.panelViewportSize) private var viewport
    private var compact: Bool { (viewport?.height ?? 760) < 700 }

    var body: some View {
        VStack(spacing: 18) {
            productInfo
                .frame(maxWidth: .infinity)
                .padding(compact ? 18 : 28)
                .cardSurface(cornerRadius: LayoutRules.cardRadius)

            HStack(spacing: 8) {
                projectLink("GitHub", icon: "chevron.left.forwardslash.chevron.right", path: "")
                projectLink(L10n.tr("about.feedback"), icon: "bubble.left", path: "/issues")
                projectLink(L10n.tr("about.licenses"), icon: "doc.text", path: "/blob/main/Sources/AILSA_SS/Resources/THIRD_PARTY_NOTICES.md")
            }
            Text("© 2026 KZCFG · MIT")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
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
}

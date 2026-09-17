import SwiftUI
import AppKit

struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            if let url = Bundle.main.url(forResource: "AILSASubSwitch", withExtension: "icns"),
               let icon = NSImage(contentsOf: url) {
                Image(nsImage: icon).resizable().frame(width: 112, height: 112)
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

        }
        .padding(28)
        .frame(width: 430)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

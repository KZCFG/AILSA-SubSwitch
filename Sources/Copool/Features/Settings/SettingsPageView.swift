import SwiftUI

struct SettingsPageView: View {
    @ObservedObject var model: SettingsPageModel

    var body: some View {
        SettingsPageContent(model: model)
            .appCanvas()
    }
}

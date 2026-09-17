import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

enum PlatformClipboard {
    static func copy(_ value: String?) {
        guard let value, !value.isEmpty else { return }
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #elseif canImport(UIKit)
        UIPasteboard.general.string = value
        #endif
    }
}

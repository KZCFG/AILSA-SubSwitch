import Foundation

enum NoticeStyle {
    case success
    case info
    case error
}

struct NoticeMessage: Equatable {
    var style: NoticeStyle
    var text: String

    var autoDismissDelay: Duration {
        switch style {
        case .success, .info:
            return .seconds(3)
        case .error:
            return .seconds(5)
        }
    }
}

@MainActor
final class NoticeAutoDismissScheduler {
    private var dismissTask: Task<Void, Never>?

    func schedule(_ notice: NoticeMessage?, onDismiss: @escaping @MainActor () -> Void) {
        dismissTask?.cancel()
        guard let notice else { return }

        dismissTask = Task {
            try? await Task.sleep(for: notice.autoDismissDelay)
            guard !Task.isCancelled else { return }
            onDismiss()
        }
    }

    func cancel() {
        dismissTask?.cancel()
        dismissTask = nil
    }
}

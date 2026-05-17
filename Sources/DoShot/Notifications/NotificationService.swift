import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private var requestedAuth = false
    private var onClickReveal: ((String) -> Void)?
    private var onClickReopenModal: (() -> Void)?

    func bootstrap(onClickReveal: @escaping (String) -> Void,
                   onClickReopenModal: @escaping () -> Void) {
        self.onClickReveal = onClickReveal
        self.onClickReopenModal = onClickReopenModal
        UNUserNotificationCenter.current().delegate = self
    }

    private func ensureAuth() {
        guard !requestedAuth else { return }
        requestedAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func postSuccess(result: RunResult) {
        ensureAuth()
        let content = UNMutableNotificationContent()
        content.title = result.summary
        content.subtitle = result.subtitle
        if let target = result.saveTarget {
            content.userInfo = ["kind": "reveal", "target": target]
        } else {
            content.userInfo = ["kind": "summary"]
        }
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func postError(error: RunError, runId: String) {
        ensureAuth()
        let content = UNMutableNotificationContent()
        content.title = "DoShot failed"
        content.subtitle = error.errorDescription ?? "Unknown error"
        content.userInfo = ["kind": "error", "runId": runId]
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let kind = info["kind"] as? String ?? ""
        Task { @MainActor in
            switch kind {
            case "reveal":
                if let target = info["target"] as? String { self.onClickReveal?(target) }
            case "error":
                self.onClickReopenModal?()
            default:
                break
            }
            completionHandler()
        }
    }
}

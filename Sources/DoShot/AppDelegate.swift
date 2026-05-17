import AppKit
import SwiftUI
import KeyboardShortcuts
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!

    let settings = SettingsModel()
    let notifications = NotificationService()
    let menuBar = MenuBarController()
    let capture = CaptureService()
    let runStore = RunStore()

    private var modalController: ModalWindowController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var accessibilityPollTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.setActivationPolicy(.accessory)

        menuBar.install(
            onCapture: { [weak self] in self?.triggerCapture() },
            onSettings: { [weak self] in self?.openSettings() },
            onQuit: { NSApp.terminate(nil) }
        )

        notifications.bootstrap(onClickReveal: { [weak self] path in
            self?.revealInFinder(path: path)
        }, onClickReopenModal: { [weak self] in
            self?.modalController?.bringToFront()
        })

        KeyboardShortcuts.onKeyUp(for: .capture) { [weak self] in
            self?.triggerCapture()
        }

        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.openOnboarding()
            }
        }

        refreshAccessibilityState()
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshAccessibilityState() }
        }
    }

    func triggerCapture() {
        Task { @MainActor in
            do {
                let runDir = try runStore.createRunDirectory()
                let imageURL = runDir.appendingPathComponent("capture.png")
                let success = try await capture.captureRegion(to: imageURL)
                guard success else {
                    try? FileManager.default.removeItem(at: runDir)
                    return
                }
                try runStore.writeMeta(runDir: runDir, instruction: nil)
                copyCaptureToPasteboard(imageURL: imageURL)
                showModal(runDir: runDir, imageURL: imageURL)
            } catch {
                notifications.postError(error: .unknown(message: error.localizedDescription), runId: "—")
            }
        }
    }

    @MainActor
    private func showModal(runDir: URL, imageURL: URL) {
        if let existing = modalController {
            existing.close()
        }
        let controller = ModalWindowController(
            runDir: runDir,
            imageURL: imageURL,
            settings: settings,
            notifications: notifications
        )
        modalController = controller
        controller.show()
    }

    func openSettings() {
        if let existing = settingsWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: SettingsSheet(settings: settings).environmentObject(settings))
        let window = NSWindow(contentViewController: host)
        window.title = "DoShot Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openOnboarding() {
        if let existing = onboardingWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: OnboardingSheet(settings: settings, onDone: { [weak self] in
            self?.settings.hasCompletedOnboarding = true
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
        }).environmentObject(settings))
        let window = NSWindow(contentViewController: host)
        window.title = "Welcome to DoShot"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 560, height: 600))
        window.center()
        window.isReleasedWhenClosed = false
        onboardingWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func refreshAccessibilityState() {
        let trusted = AXIsProcessTrusted()
        menuBar.setAccessibilityWarning(visible: !trusted)
        settings.accessibilityGranted = trusted
    }

    /// Mirror macOS's built-in screenshot "Copy" behavior: put the captured
    /// PNG on the system pasteboard so the user can `⌘V` it anywhere
    /// immediately, in addition to running the DoShot action.
    private func copyCaptureToPasteboard(imageURL: URL) {
        guard let data = try? Data(contentsOf: imageURL),
              let image = NSImage(data: data) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        // Write both the NSImage (for receivers that want a typed image) and
        // the raw PNG bytes (for receivers that key on data type).
        pb.writeObjects([image])
        pb.setData(data, forType: .png)
    }

    private func revealInFinder(path: String) {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

extension KeyboardShortcuts.Name {
    static let capture = Self("capture", default: .init(.four, modifiers: [.control, .shift]))
}

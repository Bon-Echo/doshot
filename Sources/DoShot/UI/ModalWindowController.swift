import AppKit
import SwiftUI

@MainActor
final class ModalWindowController {
    private let window: NSWindow
    private let state: RunState
    private let executor: ClaudeExecutor

    init(runDir: URL, imageURL: URL, settings: SettingsModel, notifications: NotificationService) {
        self.state = RunState(runDir: runDir, imageURL: imageURL)
        self.executor = ClaudeExecutor(settings: settings, notifications: notifications)

        let frame = NSRect(x: 0, y: 0, width: 420, height: 480)
        // Pure .borderless — combining .borderless with .titled produced a
        // phantom title bar that threw off positioning math and let the modal
        // open off-screen on some setups. The window's own Cancel button + ⌘W
        // keyboard shortcut + onExitCommand cover what .closable used to.
        let win = FocusableBorderlessWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isMovableByWindowBackground = true
        win.level = .floating
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        self.window = win

        let view = ModalView(
            state: state,
            settings: settings,
            onRun: { [weak self] instruction in self?.run(instruction: instruction) },
            onCancel: { [weak self] in self?.close() },
            onCopyError: { [weak self] in self?.copyError() }
        )
        let host = NSHostingController(rootView: view.environmentObject(settings))
        host.view.wantsLayer = true
        host.view.layer?.cornerRadius = 14
        host.view.layer?.masksToBounds = true
        win.contentViewController = host
    }

    func show() {
        positionBottomRight()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func bringToFront() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window.orderOut(nil)
    }

    private func positionBottomRight() {
        let screen = NSScreen.screenContainingMouse() ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let inset: CGFloat = 24
        let size = window.frame.size
        var x = visible.maxX - size.width - inset
        var y = visible.minY + inset
        // Clamp inside the visible frame so multi-monitor edge cases or a
        // stale frame.size can't push the modal partially off-screen
        // (the "stuck on the right" bug).
        x = max(visible.minX + inset, min(x, visible.maxX - size.width - inset))
        y = max(visible.minY + inset, min(y, visible.maxY - size.height - inset))
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func run(instruction: String) {
        state.instruction = instruction
        state.phase = .running
        // Dispatch to background: hide the modal immediately and rely on the
        // success/error toasts to surface the outcome. On error, the
        // notification's click handler re-opens the modal so the user can
        // hit Copy Error.
        window.orderOut(nil)
        Task {
            await executor.run(state: state) { [weak self] phase in
                guard let self else { return }
                self.state.phase = phase
                if case .failed = phase {
                    self.bringToFront()
                }
            }
        }
    }

    private func copyError() {
        guard case .failed(let err) = state.phase else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(err.copyPayload, forType: .string)
    }
}

extension NSScreen {
    static func screenContainingMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(mouse) })
    }
}

/// A .borderless NSWindow that can still become key/main — required so the
/// instruction TextField receives focus and the ⌘↩/⌘W shortcuts fire.
final class FocusableBorderlessWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

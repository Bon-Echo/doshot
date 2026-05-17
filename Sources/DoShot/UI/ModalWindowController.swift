import AppKit
import SwiftUI

@MainActor
final class ModalWindowController {
    /// Single source of truth for modal dimensions. Match in ModalView's `.frame(...)`.
    static let modalSize = NSSize(width: 440, height: 500)

    private let window: NSWindow
    private let state: RunState
    private let executor: ClaudeExecutor

    init(runDir: URL, imageURL: URL, settings: SettingsModel, notifications: NotificationService) {
        self.state = RunState(runDir: runDir, imageURL: imageURL)
        self.executor = ClaudeExecutor(settings: settings, notifications: notifications)

        let frame = NSRect(origin: .zero, size: Self.modalSize)
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
        // Defeat macOS window restoration so an old (buggy) saved position
        // can't follow the user across builds.
        win.isRestorable = false
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
        // Re-assert position on the next run-loop tick: NSHostingController
        // can adjust the window's frame after first display based on the
        // SwiftUI intrinsic size, which would otherwise push the right edge
        // past the screen.
        DispatchQueue.main.async { [weak self] in
            self?.positionBottomRight()
        }
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
        // Use the constant size rather than `window.frame.size` — the latter
        // can return the initial contentRect before NSHostingController has
        // laid out, OR a post-layout grown size — either way it's an unreliable
        // basis for "bottom-right minus inset". Use the canonical size and let
        // the SwiftUI content match.
        let size = Self.modalSize
        var x = visible.maxX - size.width - inset
        var y = visible.minY + inset
        // Clamp inside the visible frame as a belt-and-suspenders safety net.
        x = max(visible.minX + inset, min(x, visible.maxX - size.width - inset))
        y = max(visible.minY + inset, min(y, visible.maxY - size.height - inset))
        // Force the full frame (origin + size) so a post-layout resize can't
        // grow the window past the visible edge.
        window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
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

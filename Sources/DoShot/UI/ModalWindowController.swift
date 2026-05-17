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
        let win = NSWindow(
            contentRect: frame,
            styleMask: [.borderless, .titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
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
        let origin = NSPoint(
            x: visible.maxX - size.width - inset,
            y: visible.minY + inset
        )
        window.setFrameOrigin(origin)
    }

    private func run(instruction: String) {
        state.instruction = instruction
        state.phase = .running
        Task {
            await executor.run(state: state) { [weak self] phase in
                guard let self else { return }
                self.state.phase = phase
                switch phase {
                case .done:
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                        if case .done = self?.state.phase {
                            self?.close()
                        }
                    }
                case .failed:
                    break
                default:
                    break
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

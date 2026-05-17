import AppKit

final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var captureItem: NSMenuItem?
    private var settingsItem: NSMenuItem?
    private var quitItem: NSMenuItem?
    private var captureHandler: (() -> Void)?
    private var settingsHandler: (() -> Void)?
    private var quitHandler: (() -> Void)?
    private var accessibilityWarning = false

    func install(onCapture: @escaping () -> Void, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        captureHandler = onCapture
        settingsHandler = onSettings
        quitHandler = onQuit

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "DoShot")
        item.button?.image?.isTemplate = true

        let menu = NSMenu()
        let capture = NSMenuItem(title: "Capture", action: #selector(handleCapture), keyEquivalent: "")
        capture.target = self
        menu.addItem(capture)
        captureItem = capture

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(handleSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        settingsItem = settings

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit DoShot", action: #selector(handleQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        quitItem = quit

        item.menu = menu
        statusItem = item
        redrawIcon()
    }

    func setAccessibilityWarning(visible: Bool) {
        guard accessibilityWarning != visible else { return }
        accessibilityWarning = visible
        redrawIcon()
    }

    private func redrawIcon() {
        guard let button = statusItem?.button else { return }
        let base = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "DoShot") ?? NSImage()
        base.isTemplate = true
        if !accessibilityWarning {
            button.image = base
            button.toolTip = "DoShot"
            return
        }
        let size = NSSize(width: base.size.width + 4, height: base.size.height + 4)
        let composite = NSImage(size: size)
        composite.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: base.size))
        // yellow dot overlay top-right
        NSColor.systemYellow.setFill()
        let dot = NSBezierPath(ovalIn: NSRect(x: base.size.width - 4, y: base.size.height - 4, width: 7, height: 7))
        dot.fill()
        composite.unlockFocus()
        composite.isTemplate = false
        button.image = composite
        button.toolTip = "DoShot — Accessibility permission required for hotkey"
    }

    @objc private func handleCapture() { captureHandler?() }
    @objc private func handleSettings() { settingsHandler?() }
    @objc private func handleQuit() { quitHandler?() }
}

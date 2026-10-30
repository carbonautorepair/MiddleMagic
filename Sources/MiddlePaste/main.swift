import AppKit
import ApplicationServices
import MiddlePasteCore

final class MiddlePasteApp: NSObject, NSApplicationDelegate {
    private let bank = MiddleBuffer()
    private var mouse: MiddleMouseController!
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var bufferItem: NSMenuItem!
    private var statusMessage: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        mouse = MiddleMouseController(bank: bank)
        mouse.onChange = { [weak self] in self?.updateMenu() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "MM"
        let menu = NSMenu(title: "MiddleMagic")

        enabledItem = NSMenuItem(title: "Enabled", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = .on
        menu.addItem(enabledItem)

        statusMessage = NSMenuItem(title: "Checking Accessibility…", action: nil, keyEquivalent: "")
        statusMessage.isEnabled = false
        menu.addItem(statusMessage)

        let permissionItem = NSMenuItem(title: "Request Accessibility Permission", action: #selector(requestPermission), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)

        let retryItem = NSMenuItem(title: "Retry mouse listener", action: #selector(retry), keyEquivalent: "")
        retryItem.target = self
        menu.addItem(retryItem)
        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit MiddleMagic", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        statusItem.menu = menu

        Log.write("launch: trusted=\(AXIsProcessTrusted())")
        _ = mouse.start()
        updateMenu()
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            guard let self, !self.mouse.isActive else { return }
            if self.mouse.start() { self.updateMenu() }
        }
    }

    @objc private func toggleEnabled() {
        mouse.enabled.toggle()
        updateMenu()
    }

    @objc private func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        updateMenu()
    }

    @objc private func retry() {
        mouse.stop()
        _ = mouse.start()
        updateMenu()
    }

    @objc private func quit() {
        mouse.stop()
        NSApplication.shared.terminate(nil)
    }

    private func updateMenu() {
        enabledItem.state = mouse.enabled ? .on : .off
        statusMessage.title = AXIsProcessTrusted()
            ? "Accessibility: allowed (retry if inactive)"
            : "Accessibility: permission required"
    }
}

let app = NSApplication.shared
let appDelegate = MiddlePasteApp()
app.delegate = appDelegate
app.setActivationPolicy(.accessory)
app.run()

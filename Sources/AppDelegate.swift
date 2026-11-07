import AppKit
import ApplicationServices
import CoreGraphics
import ServiceManagement
import os

let log = Logger(subsystem: "com.badriram.DockPeek", category: "app")

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let settings = Settings()
    private var controller: PreviewController!
    private let watcher = DockWatcher()
    private var trustTimer: Timer?
    private var onboarding: OnboardingWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = PreviewController(settings: settings)
        watcher.onHover = { [weak self] h in self?.controller.dockHovered(h) }
        watcher.onHoverEnd = { [weak self] in self?.controller.dockHoverEnded() }
        controller.hoveredPID = { [weak self] in self?.watcher.currentHover()?.app.processIdentifier }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "DockPeek")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        ensureAccessibility()
    }

    private func ensureAccessibility() {
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts) {
            watcher.start()
            return
        }
        log.info("Waiting for Accessibility permission")
        let window = OnboardingWindow()
        onboarding = window
        window.present()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] t in
            guard AXIsProcessTrusted() else { return }
            t.invalidate()
            self?.onboarding?.close()
            self?.onboarding = nil
            self?.watcher.start()
        }
    }

    // MARK: Menu (rebuilt each time it opens so permission status is live)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let ax = AXIsProcessTrusted()
        let sr = CGPreflightScreenCaptureAccess()

        let title = NSMenuItem(title: "DockPeek", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let thumbs = item("Show window thumbnails", #selector(toggleThumbnails))
        thumbs.state = settings.thumbnails ? .on : .off
        menu.addItem(thumbs)
        if settings.thumbnails && !sr {
            menu.addItem(disabled("    Needs Screen Recording - showing titles only"))
        }

        let login = item("Launch at login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(disabled("Permissions"))
        menu.addItem(item(ax ? "    \(accessibilityPaneName): granted"
                             : "    \(accessibilityPaneName): not granted - Open Settings…",
                          #selector(openAccessibilitySettings)))
        menu.addItem(item(sr ? "    Screen Recording: granted" : "    Screen Recording: not granted (thumbnails only)",
                          #selector(openScreenRecordingSettings)))
        if sr && !settings.thumbnails {
            menu.addItem(disabled("    Tip: thumbnails are off, you can revoke Screen Recording"))
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit DockPeek", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    @objc private func toggleThumbnails() {
        settings.thumbnails.toggle()
        controller.hide()
        if settings.thumbnails && !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            log.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @objc private func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    @objc private func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func open(_ s: String) {
        if let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

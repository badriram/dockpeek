import AppKit

/// Name of the Accessibility pane differs by macOS version (renamed in macOS 27).
var accessibilityPaneName: String {
    ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
        ? "Device Control and Data Access" : "Accessibility"
}

/// Shown while Accessibility isn't granted. Closes itself once it is.
final class OnboardingWindow: NSWindow {
    init() {
        super.init(contentRect: CGRect(x: 0, y: 0, width: 460, height: 250),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "DockPeek needs one permission"
        isReleasedWhenClosed = false
        center()

        let body = NSTextField(wrappingLabelWithString: """
        To show window previews when you hover a Dock icon, DockPeek needs \
        “\(accessibilityPaneName)” access. It uses it only to see which Dock icon is \
        hovered and to bring the window you click to the front.

        DockPeek is sandboxed with no network access and cannot read your files.

        1. Click “Open Settings”.
        2. If DockPeek isn't listed, click + and choose DockPeek in Applications \
        (or drag it in from the Finder window).
        3. Turn it on. This window closes by itself.
        """)
        body.frame = CGRect(x: 20, y: 60, width: 420, height: 175)

        let open = NSButton(title: "Open Settings", target: self, action: #selector(openSettings))
        open.bezelStyle = .rounded
        open.keyEquivalent = "\r"
        open.frame = CGRect(x: 300, y: 15, width: 140, height: 32)

        let reveal = NSButton(title: "Show in Finder", target: self, action: #selector(revealApp))
        reveal.bezelStyle = .rounded
        reveal.frame = CGRect(x: 160, y: 15, width: 140, height: 32)

        let view = NSView(frame: contentLayoutRect)
        [body, open, reveal].forEach(view.addSubview)
        contentView = view
    }

    func present() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }

    @objc private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func revealApp() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
}

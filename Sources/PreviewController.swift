import AppKit
import CoreGraphics

/// Decides when to show/hide the preview. Uses only NSEvent.mouseLocation (no permission needed)
/// to keep the panel open while the pointer travels from the Dock icon into it.
final class PreviewController {
    private let settings: Settings
    private let panel = PreviewPanel()
    private var current: DockHover?
    private var windows: [WindowEntry] = []
    private var showWork: DispatchWorkItem?
    private var hideTimer: Timer?
    private var generation = 0
    private var keepAliveRect: CGRect = .zero // hovered icon + gap to the panel (Cocoa coords)
    var hoveredPID: () -> pid_t? = { nil }

    init(settings: Settings) { self.settings = settings }

    func dockHovered(_ h: DockHover) {
        if panel.isVisible, current?.app.processIdentifier == h.app.processIdentifier { return }
        showWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.show(h) }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (panel.isVisible ? 0 : 0.25), execute: work)
    }

    func dockHoverEnded() {
        showWork?.cancel()
        showWork = nil
    }

    /// Runs only while the panel is visible. Hides once the pointer has left the panel,
    /// the hovered icon and the gap between them, and the Dock no longer reports this app hovered.
    private func startHideTimer() {
        guard hideTimer == nil else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.checkHide()
        }
    }

    private func checkHide() {
        let mouse = NSEvent.mouseLocation
        if panel.frame.insetBy(dx: -14, dy: -14).contains(mouse) { return }
        if keepAliveRect.contains(mouse) { return }
        if let pid = hoveredPID(), pid == current?.app.processIdentifier { return }
        hide()
    }

    private func stopHideTimer() {
        hideTimer?.invalidate()
        hideTimer = nil
    }

    func hide() {
        stopHideTimer()
        showWork?.cancel()
        generation += 1 // cancels any in-flight thumbnail capture
        panel.orderOut(nil)
        panel.clear()
        current = nil
        windows = []
    }

    private func show(_ h: DockHover) {
        let list = WindowProvider.windows(for: h.app)
        guard !list.isEmpty else { hide(); return }
        generation += 1
        let gen = generation
        current = h
        windows = list

        let useThumbs = settings.thumbnails && CGPreflightScreenCaptureAccess()
        panel.display(
            app: h.app, windows: list, thumbnails: useThumbs, iconFrame: h.iconFrame,
            onSelect: { [weak self] i in
                guard let self, i < self.windows.count else { return }
                WindowProvider.focus(self.windows[i], app: h.app)
                self.hide()
            },
            onClose: { [weak self] i in
                guard let self, i < self.windows.count else { return }
                WindowProvider.close(self.windows[i])
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, self.generation == gen else { return }
                    self.show(h) // refresh list after close
                }
            }
        )

        // Bridge from the icon to the nearest point on the panel so moving the pointer up into it
        // doesn't close it.
        let icon = AX.toCocoa(h.iconFrame)
        let f = panel.frame
        let nearest = CGPoint(x: min(max(icon.midX, f.minX), f.maxX), y: min(max(icon.midY, f.minY), f.maxY))
        keepAliveRect = icon.insetBy(dx: -4, dy: -4).union(CGRect(origin: nearest, size: CGSize(width: 1, height: 1)))
        startHideTimer()

        guard useThumbs else { return }
        let pid = h.app.processIdentifier
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        Task { @MainActor [weak self] in
            let images = await WindowProvider.thumbnails(pid: pid, windows: list, maxPixelWidth: 204 * scale)
            guard let self, self.generation == gen else { return }
            self.panel.setThumbnails(images)
        }
    }
}

final class Settings {
    private let defaults = UserDefaults.standard
    /// Off by default: no Screen Recording is ever requested unless the user opts in.
    var thumbnails: Bool {
        get { defaults.bool(forKey: "thumbnails") }
        set { defaults.set(newValue, forKey: "thumbnails") }
    }
}

import AppKit
import ApplicationServices
import os

struct DockHover {
    let app: NSRunningApplication
    let iconFrame: CGRect // Accessibility coordinates (top-left origin)
}

/// Watches the Dock's accessibility tree for "selected" (hovered) icons.
/// This is event-driven: no polling, no global mouse/keyboard monitoring.
final class DockWatcher {
    var onHover: ((DockHover) -> Void)?
    var onHoverEnd: (() -> Void)?
    private(set) var isHovering = false

    private var observer: AXObserver?
    private var dockList: AXUIElement?
    private var launchObserver: NSObjectProtocol?
    private var retryWork: DispatchWorkItem?

    func start() {
        attach()
        guard launchObserver == nil else { return }
        // Re-attach if the Dock restarts (e.g. `killall Dock`).
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.dock" else { return }
            self?.scheduleRetry(after: 1.0)
        }
    }

    private func scheduleRetry(after delay: TimeInterval) {
        retryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.attach() }
        retryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observer = nil
        dockList = nil
    }

    private func attach() {
        detach()
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            scheduleRetry(after: 2.0); return
        }
        let pid = dock.processIdentifier
        let dockEl = AXUIElementCreateApplication(pid)
        guard let list = AX.elements(dockEl, kAXChildrenAttribute)
            .first(where: { AX.string($0, kAXRoleAttribute) == kAXListRole }) else {
            var v: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(dockEl, kAXChildrenAttribute as CFString, &v)
            log.error("Dock list not found (AXError \(err.rawValue, privacy: .public), trusted=\(AXIsProcessTrusted(), privacy: .public)); retrying")
            scheduleRetry(after: 2.0); return
        }

        var obs: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<DockWatcher>.fromOpaque(refcon).takeUnretainedValue().selectionChanged()
        }
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else {
            log.error("AXObserverCreate failed"); return
        }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let err = AXObserverAddNotification(obs, list, kAXSelectedChildrenChangedNotification as CFString, refcon)
        guard err == .success else {
            log.error("AXObserverAddNotification failed: \(err.rawValue, privacy: .public)")
            scheduleRetry(after: 2.0); return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
        dockList = list
        let count = AX.elements(list, kAXChildrenAttribute).count
        log.info("Attached to Dock (\(count, privacy: .public) items)")
    }

    /// Live query of the Dock's hovered app icon. The Dock notifies when an icon becomes hovered
    /// but (on macOS 27) not reliably when hover ends, so callers re-check this while a preview is open.
    func currentHover() -> DockHover? {
        guard let dockList,
              let item = AX.elements(dockList, kAXSelectedChildrenAttribute).first,
              AX.string(item, kAXSubroleAttribute) == "AXApplicationDockItem",
              let url = AX.url(item, kAXURLAttribute),
              let frame = AX.frame(item),
              let app = Self.runningApp(at: url)
        else { return nil }
        return DockHover(app: app, iconFrame: frame)
    }

    private func selectionChanged() {
        if let hover = currentHover() {
            isHovering = true
            onHover?(hover)
        } else if isHovering {
            isHovering = false
            onHoverEnd?()
        }
    }

    private static func runningApp(at url: URL) -> NSRunningApplication? {
        let target = url.standardizedFileURL.resolvingSymlinksInPath().path
        return NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == target
        }
    }
}

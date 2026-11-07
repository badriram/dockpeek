import AppKit
import ApplicationServices
import ScreenCaptureKit

struct WindowEntry {
    let ax: AXUIElement
    let pid: pid_t // owner, verified when the entry is built
    let title: String
    let frame: CGRect // Accessibility coordinates
    let minimized: Bool
}

enum WindowProvider {
    /// All Accessibility calls to other apps run on this queue, never the main thread, so a slow or
    /// hostile app can't freeze DockPeek's UI.
    static let axQueue = DispatchQueue(label: "com.badriram.DockPeek.ax", qos: .userInitiated)
    static let maxWindows = 30
    static let listDeadline: TimeInterval = 1.0

    /// Caps how long any single Accessibility call to any app can block (default is ~6 s).
    static func configureTimeouts() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)
    }

    static func pid(of el: AXUIElement) -> pid_t? {
        var p: pid_t = 0
        return AXUIElementGetPid(el, &p) == .success ? p : nil
    }

    /// Window list via Accessibility only (no Screen Recording needed). Off the main thread, capped at
    /// `maxWindows`, stops at `listDeadline`, and drops any element the app hands back that isn't its own.
    static func loadWindows(for app: NSRunningApplication, completion: @escaping ([WindowEntry]) -> Void) {
        let owner = app.processIdentifier
        let fallbackTitle = app.localizedName ?? "Window"
        axQueue.async {
            let start = Date()
            let el = AXUIElementCreateApplication(owner)
            var result: [WindowEntry] = []
            for w in AX.elements(el, kAXWindowsAttribute).prefix(maxWindows) {
                if Date().timeIntervalSince(start) > listDeadline { break }
                guard pid(of: w) == owner else { continue }
                let sub = AX.string(w, kAXSubroleAttribute)
                guard sub == kAXStandardWindowSubrole || sub == kAXDialogSubrole else { continue }
                let title = AX.string(w, kAXTitleAttribute) ?? ""
                result.append(WindowEntry(
                    ax: w, pid: owner,
                    title: title.isEmpty ? fallbackTitle : String(title.prefix(200)),
                    frame: AX.frame(w) ?? .zero,
                    minimized: AX.bool(w, kAXMinimizedAttribute) ?? false
                ))
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /// One still frame per window, captured on demand, kept in memory only.
    /// Only called when the user enabled thumbnails AND granted Screen Recording.
    @MainActor
    static func thumbnails(pid: pid_t, windows: [WindowEntry], maxPixelWidth: CGFloat) async -> [Int: CGImage] {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false) else {
            return [:]
        }
        var pool = content.windows.filter {
            $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 40
        }
        var result: [Int: CGImage] = [:]
        for (i, w) in windows.enumerated() where !w.minimized {
            guard let idx = pool.firstIndex(where: { framesMatch($0.frame, w.frame) })
                    ?? pool.firstIndex(where: { $0.title == w.title }) else { continue }
            let sc = pool.remove(at: idx)
            let cfg = SCStreamConfiguration()
            let scale = min(1, maxPixelWidth / max(sc.frame.width, 1))
            cfg.width = max(1, Int(sc.frame.width * scale))
            cfg.height = max(1, Int(sc.frame.height * scale))
            cfg.showsCursor = false
            cfg.ignoreShadowsSingleWindow = true
            let filter = SCContentFilter(desktopIndependentWindow: sc)
            if let img = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) {
                result[i] = img
            }
        }
        return result
    }

    private static func framesMatch(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 3 && abs(a.minY - b.minY) < 3 &&
        abs(a.width - b.width) < 3 && abs(a.height - b.height) < 3
    }

    /// Activate the app first, then raise the chosen window. Activation completes asynchronously and
    /// brings the app's previously focused window forward, so raising before (or only once) races with
    /// it and sometimes lands on the wrong window. Re-check and re-raise until the app reports our
    /// window as focused. Accessibility calls run on `axQueue`.
    static func focus(_ w: WindowEntry, app: NSRunningApplication) {
        guard w.pid == app.processIdentifier else { return }
        app.activate()
        axQueue.async {
            guard pid(of: w.ax) == w.pid else { return }
            if w.minimized {
                AXUIElementSetAttributeValue(w.ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            let appEl = AXUIElementCreateApplication(w.pid)
            AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
            raise(w.ax)
            ensureFocused(w.ax, appEl: appEl, attemptsLeft: 5)
        }
    }

    private static func raise(_ win: AXUIElement) {
        AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(win, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private static func ensureFocused(_ win: AXUIElement, appEl: AXUIElement, attemptsLeft: Int) {
        guard attemptsLeft > 0 else { return }
        axQueue.asyncAfter(deadline: .now() + 0.06) {
            if let focused = AX.element(appEl, kAXFocusedWindowAttribute), CFEqual(focused, win) { return }
            raise(win)
            ensureFocused(win, appEl: appEl, attemptsLeft: attemptsLeft - 1)
        }
    }

    /// Presses the window's close button, but only if it really is a close button belonging to that
    /// window and app, rather than whatever element the app chooses to return.
    static func close(_ w: WindowEntry) {
        axQueue.async {
            guard pid(of: w.ax) == w.pid,
                  let button = AX.element(w.ax, kAXCloseButtonAttribute),
                  pid(of: button) == w.pid,
                  AX.string(button, kAXSubroleAttribute) == kAXCloseButtonSubrole,
                  let owner = AX.element(button, kAXWindowAttribute) ?? AX.element(button, kAXParentAttribute),
                  CFEqual(owner, w.ax)
            else { return }
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }
}

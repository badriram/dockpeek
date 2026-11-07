import AppKit
import ApplicationServices
import ScreenCaptureKit

struct WindowEntry {
    let ax: AXUIElement
    let title: String
    let frame: CGRect // Accessibility coordinates
    let minimized: Bool
}

enum WindowProvider {
    /// Window list via Accessibility only. Needs no Screen Recording permission.
    static func windows(for app: NSRunningApplication) -> [WindowEntry] {
        let el = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(el, 0.5) // never hang on an unresponsive app
        return AX.elements(el, kAXWindowsAttribute).compactMap { w in
            let sub = AX.string(w, kAXSubroleAttribute)
            guard sub == kAXStandardWindowSubrole || sub == kAXDialogSubrole else { return nil }
            let title = AX.string(w, kAXTitleAttribute) ?? ""
            return WindowEntry(
                ax: w,
                title: title.isEmpty ? (app.localizedName ?? "Window") : title,
                frame: AX.frame(w) ?? .zero,
                minimized: AX.bool(w, kAXMinimizedAttribute) ?? false
            )
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

    static func focus(_ w: WindowEntry, app: NSRunningApplication) {
        if w.minimized {
            AXUIElementSetAttributeValue(w.ax, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appEl, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(w.ax, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(w.ax, kAXRaiseAction as CFString)
        app.activate()
    }

    static func close(_ w: WindowEntry) {
        if let button = AX.element(w.ax, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }
}

import Foundation

// The App Sandbox entitlement can't be used: on macOS 27 it blocks Accessibility reads of the Dock
// (AXError -25204) even when the app is trusted. Instead DockPeek sandboxes itself at launch with a
// kernel-enforced profile that allows Accessibility but forbids networking and reading/writing your files.
// Once applied, a sandbox can never be lifted or loosened by the process.

@_silgen_name("sandbox_init")
private func sandbox_init(_ profile: UnsafePointer<CChar>, _ flags: UInt64,
                          _ errorbuf: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

@_silgen_name("sandbox_free_error")
private func sandbox_free_error(_ errorbuf: UnsafeMutablePointer<CChar>)

enum SelfSandbox {
    static let bundleID = "com.badriram.DockPeek"

    struct Paths {
        let home: String       // canonical home folder
        let bundle: String     // this app's bundle (may live under home in dev builds)
        let executable: String
        let temp: String       // DockPeek's own temp folder, inside the per-user temp dir
        let cache: String      // DockPeek's own cache folder, inside the per-user cache dir
        let prefs: String      // DockPeek's own preferences plist
    }

    /// Resolve symlinks (e.g. /var -> /private/var) so path filters match what the kernel sees.
    static func canonical(_ path: String) -> String {
        guard let p = realpath(path, nil) else { return path }
        defer { free(p) }
        return String(cString: p)
    }

    private static func darwinDir(_ name: Int32) -> String? {
        let len = confstr(name, nil, 0)
        guard len > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: len)
        guard confstr(name, &buf, len) > 0 else { return nil }
        return String(cString: buf)
    }

    /// Creates DockPeek's own temp/cache folders inside the per-user ones (which are shared by every
    /// unsandboxed app). Only these, not their shared parents, are writable once sandboxed.
    static func preparePaths() -> Paths? {
        let fm = FileManager.default
        guard let userTemp = darwinDir(_CS_DARWIN_USER_TEMP_DIR),
              let userCache = darwinDir(_CS_DARWIN_USER_CACHE_DIR),
              let exe = Bundle.main.executablePath else { return nil }
        let temp = canonical(userTemp) + "/" + bundleID
        let cache = canonical(userCache) + "/" + bundleID
        for dir in [temp, cache] {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        }
        let home = canonical(NSHomeDirectory())
        return Paths(home: home, bundle: canonical(Bundle.main.bundlePath), executable: canonical(exe),
                     temp: temp, cache: cache, prefs: home + "/Library/Preferences/\(bundleID).plist")
    }

    /// An SBPL string literal. Returns nil for paths we refuse to embed (control characters).
    static func lit(_ s: String) -> String? {
        guard !s.isEmpty, s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else { return nil }
        return "\"" + s.replacingOccurrences(of: "\\", with: "\\\\")
                       .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func profile(_ p: Paths) -> String? {
        guard let bundle = lit(p.bundle), let exe = lit(p.executable),
              let temp = lit(p.temp), let cache = lit(p.cache), let prefs = lit(p.prefs),
              let fonts = lit(p.home + "/Library/Fonts"),
              let keyboards = lit(p.home + "/Library/Keyboard Layouts"),
              let inputMethods = lit(p.home + "/Library/Input Methods"),
              let globalPrefs = lit(p.home + "/Library/Preferences/.GlobalPreferences.plist")
        else { return nil }
        return """
        (version 1)
        (allow default)

        ; No networking of any kind: no internet, no LAN, no listening sockets.
        (deny network*)

        ; Reads: nothing under /Users (your home, other users, /Users/Shared) or /Volumes
        ; (external and network drives), except this app and what macOS frameworks need.
        (deny file-read-data file-read-xattr (subpath "/Users") (subpath "/Volumes"))
        (allow file-read-data file-read-xattr
               (subpath \(bundle)) (subpath \(fonts)) (subpath \(keyboards)) (subpath \(inputMethods))
               (literal \(prefs)) (literal \(globalPrefs)))

        ; Writes: only DockPeek's own temp and cache folders, its own settings file and /dev/null.
        (deny file-write*)
        (allow file-write* (subpath \(temp)) (subpath \(cache)) (literal \(prefs)) (literal "/dev/null"))

        ; Cannot launch other programs.
        (deny process-exec (require-not (literal \(exe))))
        """
    }

    /// Fail closed: if the sandbox can't be built or applied, DockPeek refuses to run.
    static func apply() {
        guard let paths = preparePaths(), let p = profile(paths) else {
            log.fault("Self-sandbox: unusable paths, refusing to run")
            exit(1)
        }
        var err: UnsafeMutablePointer<CChar>?
        if sandbox_init(p, 0, &err) != 0 {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            if let err { sandbox_free_error(err) }
            log.fault("Self-sandbox failed, refusing to run: \(msg, privacy: .public)")
            exit(1)
        }
        log.info("Self-sandbox applied (no network, no personal files)")
    }
}

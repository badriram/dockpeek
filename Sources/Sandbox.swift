import Foundation

// The App Sandbox entitlement can't be used: on macOS 27 it blocks Accessibility reads of the Dock
// (AXError -25204) even when the app is trusted. Instead DockPeek sandboxes itself at launch with a
// kernel-enforced profile that allows Accessibility but forbids networking and writing/reading your files.
// Once applied, a sandbox can never be lifted or loosened by the process.

@_silgen_name("sandbox_init")
private func sandbox_init(_ profile: UnsafePointer<CChar>, _ flags: UInt64,
                          _ errorbuf: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

@_silgen_name("sandbox_free_error")
private func sandbox_free_error(_ errorbuf: UnsafeMutablePointer<CChar>)

enum SelfSandbox {
    static func profile(home: String) -> String {
        let h = home.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let prefsPattern = NSRegularExpression.escapedPattern(for: "\(home)/Library/Preferences/com.badriram.DockPeek.plist")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        (version 1)
        (allow default)

        ; No networking of any kind: no internet, no LAN, no listening sockets.
        (deny network*)

        ; No reading your personal files. (Library is needed for system frameworks, fonts and preferences.)
        (deny file-read* (require-all (subpath "\(h)") (require-not (subpath "\(h)/Library"))))
        (deny file-read* (subpath "\(h)/Library/Mail") (subpath "\(h)/Library/Messages")
                         (subpath "\(h)/Library/Safari") (subpath "\(h)/Library/Mobile Documents")
                         (subpath "\(h)/Library/CloudStorage") (subpath "\(h)/Library/Keychains")
                         (subpath "\(h)/Library/Cookies") (subpath "\(h)/Library/Containers")
                         (subpath "\(h)/Library/Group Containers") (subpath "\(h)/Library/Application Support"))

        ; No writing files anywhere except its own settings file, the per-user temp/cache area and /dev/null.
        (deny file-write*)
        (allow file-write* (subpath "/private/var/folders") (literal "/dev/null")
                           (regex #"^\(prefsPattern)"))

        ; Cannot launch other programs.
        (deny process-exec (require-not (literal "\(Bundle.main.executablePath ?? "")")))
        """
    }

    /// Fail closed: if the sandbox can't be applied, DockPeek refuses to run.
    static func apply() {
        let p = profile(home: NSHomeDirectory())
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

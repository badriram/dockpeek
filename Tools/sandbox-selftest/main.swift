// Applies DockPeek's real sandbox profile (Sources/Sandbox.swift) to this test process, then actually
// attempts each operation. Built and run by ./verify.sh. Anything it manages to create is removed.
import Foundation
import os

let log = Logger(subsystem: "com.badriram.DockPeek.selftest", category: "selftest")
var failures = 0

func check(_ label: String, expectAllowed: Bool, _ attempt: () -> Bool) {
    let allowed = attempt()
    let ok = allowed == expectAllowed
    if !ok { failures += 1 }
    print("  \(ok ? "PASS" : "FAIL")  \(label.padding(toLength: 46, withPad: " ", startingAt: 0)) \(allowed ? "allowed" : "denied")")
}

let fm = FileManager.default
let home = SelfSandbox.canonical(NSHomeDirectory())
func confDir(_ n: Int32) -> String {
    var buf = [CChar](repeating: 0, count: 1024)
    _ = confstr(n, &buf, buf.count)
    return SelfSandbox.canonical(String(cString: buf))
}
let userTemp = confDir(_CS_DARWIN_USER_TEMP_DIR)
let userCache = confDir(_CS_DARWIN_USER_CACHE_DIR)
let tag = "dockpeek-selftest-\(getpid())"

// Direct (non-atomic) create: atomic saves stage in the shared temp folder, which is blocked by design.
func canWrite(_ path: String) -> Bool {
    let fd = open(path, O_CREAT | O_EXCL | O_WRONLY, 0o600)
    guard fd >= 0 else { return false }
    close(fd)
    unlink(path)
    return true
}
func canMkdir(_ path: String) -> Bool {
    let ok = (try? fm.createDirectory(atPath: path, withIntermediateDirectories: false)) != nil
    if ok { try? fm.removeItem(atPath: path) }
    return ok
}
func canRead(_ path: String) -> Bool { FileHandle(forReadingAtPath: path) != nil }
func canList(_ path: String) -> Bool { (try? fm.contentsOfDirectory(atPath: path)) != nil }
func firstFile(in dir: String) -> String? {
    (try? fm.contentsOfDirectory(atPath: dir))?.first.map { dir + "/" + $0 }
}

// Pick real files to read *before* sandboxing (afterwards we can't list them).
let otherPrefs = firstFile(in: home + "/Library/Preferences")
    .flatMap { $0.hasSuffix("com.badriram.DockPeek.plist") ? nil : $0 }
let font = firstFile(in: home + "/Library/Fonts")

let own = SelfSandbox.preparePaths()!
SelfSandbox.apply()
print("Sandbox applied to test process \(getpid())")

print("Network")
check("TCP connect to 1.1.1.1:443", expectAllowed: false) {
    let s = socket(AF_INET, SOCK_STREAM, 0)
    guard s >= 0 else { return false }
    defer { close(s) }
    var a = sockaddr_in()
    a.sin_family = sa_family_t(AF_INET); a.sin_port = in_port_t(443).bigEndian
    inet_pton(AF_INET, "1.1.1.1", &a.sin_addr)
    var tv = timeval(tv_sec: 3, tv_usec: 0)
    setsockopt(s, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    return withUnsafePointer(to: &a) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(s, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
        }
    }
}

print("Reading")
check("list ~/Documents", expectAllowed: false) { canList(home + "/Documents") }
check("list ~/Desktop", expectAllowed: false) { canList(home + "/Desktop") }
check("list /Users/Shared", expectAllowed: false) { canList("/Users/Shared") }
check("list ~/Library/Caches", expectAllowed: false) { canList(home + "/Library/Caches") }
if let otherPrefs { check("read another app's preferences", expectAllowed: false) { canRead(otherPrefs) } }
if let font { check("read a font in ~/Library/Fonts", expectAllowed: true) { canRead(font) } }

print("Writing")
check("create file in its own temp folder", expectAllowed: true) { canWrite(own.temp + "/" + tag) }
check("create file in its own cache folder", expectAllowed: true) { canWrite(own.cache + "/" + tag) }
check("create file in shared per-user temp folder", expectAllowed: false) { canWrite(userTemp + "/" + tag) }
check("create folder in shared per-user cache folder", expectAllowed: false) { canMkdir(userCache + "/" + tag) }
check("create file in /tmp", expectAllowed: false) { canWrite("/private/tmp/" + tag) }
check("create file in ~/Library/Preferences", expectAllowed: false) {
    canWrite(home + "/Library/Preferences/" + tag + ".plist")
}
check("save its own settings", expectAllowed: true) {
    let d = UserDefaults(suiteName: SelfSandbox.bundleID)!
    let v = UUID().uuidString
    d.set(v, forKey: "selftest")
    let ok = d.synchronize() && d.string(forKey: "selftest") == v
    d.removeObject(forKey: "selftest")
    d.synchronize()
    return ok
}

print("Programs")
check("run /bin/echo", expectAllowed: false) {
    var pid = pid_t()
    let args: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/echo"), nil]
    defer { args.forEach { free($0) } }
    return posix_spawn(&pid, "/bin/echo", nil, nil, args, nil) == 0
}

print(failures == 0 ? "\nAll self-test checks passed" : "\n\(failures) self-test check(s) FAILED")
exit(failures == 0 ? 0 : 1)

// Asks the kernel what the running DockPeek process is allowed to do.
// Build/run via ./verify.sh. Uses sandbox_check (libsystem_sandbox), read-only.
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>

enum { FILTER_NONE = 0, FILTER_PATH = 1 };
extern int sandbox_check(pid_t pid, const char *operation, int type, ...);

static int failures = 0;

static void expect(const char *label, int denied, int want_denied) {
    denied = denied != 0;
    const char *ok = (denied == want_denied) ? "PASS" : "FAIL";
    if (denied != want_denied) failures++;
    printf("  %-4s  %-46s %s\n", ok, label, denied ? "denied" : "allowed");
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: %s <pid>\n", argv[0]); return 2; }
    pid_t pid = (pid_t)atoi(argv[1]);
    const char *home = getenv("HOME");
    char docs[1024], desk[1024], ssh[1024], prefs[1024];
    snprintf(docs, sizeof docs, "%s/Documents/x", home);
    snprintf(desk, sizeof desk, "%s/Desktop/x", home);
    snprintf(ssh, sizeof ssh, "%s/.ssh/id_ed25519", home);
    snprintf(prefs, sizeof prefs, "%s/Library/Preferences/x", home);

    printf("Process %d sandboxed: %s\n", pid, sandbox_check(pid, NULL, FILTER_NONE) ? "yes" : "NO");
    expect("network-outbound (internet/LAN)", sandbox_check(pid, "network-outbound", FILTER_NONE), 1);
    expect("network-inbound / listening", sandbox_check(pid, "network-inbound", FILTER_NONE), 1);
    expect("network-bind", sandbox_check(pid, "network-bind", FILTER_NONE), 1);
    expect("read ~/Documents", sandbox_check(pid, "file-read-data", FILTER_PATH, docs), 1);
    expect("read ~/Desktop", sandbox_check(pid, "file-read-data", FILTER_PATH, desk), 1);
    expect("read ~/.ssh keys", sandbox_check(pid, "file-read-data", FILTER_PATH, ssh), 1);
    expect("write ~/Library/Preferences", sandbox_check(pid, "file-write-create", FILTER_PATH, prefs), 1);
    expect("write /tmp", sandbox_check(pid, "file-write-create", FILTER_PATH, "/private/tmp/x"), 1);
    snprintf(prefs, sizeof prefs, "%s/Library/Preferences/com.badriram.DockPeek.plist", home);
    expect("write its own settings file", sandbox_check(pid, "file-write-create", FILTER_PATH, prefs), 0);
    expect("exec /bin/sh", sandbox_check(pid, "process-exec", FILTER_PATH, "/bin/sh"), 1);
    printf(failures ? "\n%d check(s) FAILED\n" : "\nAll checks passed\n", failures);
    return failures ? 1 : 0;
}

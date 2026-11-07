// Asks the kernel whether the running DockPeek process is sandboxed with networking and exec blocked.
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
    printf("Process %d sandboxed: %s\n", pid, sandbox_check(pid, NULL, FILTER_NONE) ? "yes" : "NO");
    expect("network-outbound (internet/LAN)", sandbox_check(pid, "network-outbound", FILTER_NONE), 1);
    expect("network-inbound / listening", sandbox_check(pid, "network-inbound", FILTER_NONE), 1);
    expect("network-bind", sandbox_check(pid, "network-bind", FILTER_NONE), 1);
    expect("exec /bin/sh", sandbox_check(pid, "process-exec", FILTER_PATH, "/bin/sh"), 1);
    // File rules are checked by actually attempting them: see Tools/sandbox-selftest.
    printf(failures ? "\n%d check(s) FAILED\n" : "\nAll checks passed\n", failures);
    return failures ? 1 : 0;
}

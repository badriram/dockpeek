# CLAUDE.md

DockPeek: a lean macOS menu-bar app (Swift, no dependencies) showing window previews when hovering
Dock icons. The product is the **trust surface**: every change is weighed against the privacy
model in README.md. Features belong in [DockDoor](https://github.com/ejbills/DockDoor), not here.

## Invariants

- **No networking, no entitlements, no third-party code.** CI fails on networking APIs in `Sources/`
  or any entitlement. The only deprecated API is `sandbox_init` (Sources/Sandbox.swift).
- **Self-sandbox, not App Sandbox.** On macOS 27 the App Sandbox entitlement blocks Accessibility
  reads of the Dock (AXError -25204) even when trusted, so `main.swift` applies an SBPL profile first
  thing and fails closed. `APP_SANDBOX=1 ./build.sh` re-tests the entitlement on newer macOS.
- **Accessibility calls to other apps run on `WindowProvider.axQueue`**, with a pid ownership check
  before acting on any element. The main thread only touches the (verified, Apple-signed) Dock.
- **Opening URLs/apps via LaunchServices is accepted by design** (VulnHunt VULN-001, rejected by the
  owner): it is core app behaviour. Harden around it, keep it allowed.

## Sandbox work

`./verify.sh` is the source of truth: `Tools/sandbox-selftest` applies the real profile and attempts
every operation. Run it after any change to `Sources/Sandbox.swift`. Gotchas learned the hard way:

- `sandbox_check` answers "denied" for paths that don't exist, whatever the rules; it can't verify
  create/write rules. Test by attempting the operation.
- Atomic writes (`FileManager.createFile`, `Data.write(.atomic)`) stage in the shared per-user temp
  dir, which is blocked; only DockPeek's own `T/` and `C/` subfolders are writable.
- `NSTemporaryDirectory()` ignores `TMPDIR`; framework temp files can't be redirected that way.
- Kernel sandbox denials don't appear in `log show`, so the profile can't be tuned from logs.

## Running dev builds

The owner runs the Homebrew-installed release in `/Applications`. Leave it there: test dev builds from
`build/` (quit the release first). TCC ties grants to the code signature, so switching between a
dev build (Apple Development cert) and the release (Developer ID) needs
`tccutil reset Accessibility com.badriram.DockPeek` and a re-grant each way. Behaviour that needs a
human (hover, focus, close, thumbnails, settings persistence) gets tested by the owner before any
commit or tag.

## Releasing

Tag `vX.Y.Z` and push. `release.yml` waits for the owner's approval in the protected `release`
environment, then signs (Developer ID), notarizes, staples, attests, publishes an immutable release,
and bumps `Casks/dockpeek.rb` in `badriram/homebrew-tools`. If "Attest build provenance" fails with
a Sigstore 500, that's their outage: re-run once it recovers (nothing was published). New workflow
steps must use GitHub-owned actions pinned to a commit SHA, or Actions rejects them.

## Public repo hygiene

Releases are signed in the owner's legal name, but the repo carries none of their Apple Developer
account details: no team ID, certificate names, or personal email (git uses the GitHub noreply).
Check diffs for these before every push.

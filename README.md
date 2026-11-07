# DockPeek

Windows-style window previews when hovering Dock icons, built for the smallest possible trust surface.

## Privacy model

| | DockPeek | Why |
|---|---|---|
| Sandbox | **self-applied at launch, kernel-enforced** | `Sources/Sandbox.swift`; fails closed (won't run without it) |
| Network | **blocked** | `(deny network*)`: no internet, LAN, or listening |
| Your files | **blocked** | No reads under `/Users` (your home, other users, Shared) or `/Volumes` except your fonts and its own settings; writes only to its own temp/cache folders and settings |
| Launching programs | **blocked** | |
| Entitlements | **none** | Hardened runtime on |
| Accessibility | required | Detect hovered Dock icon, list/focus/close windows |
| Screen Recording | **optional, off by default** | Only for thumbnails; never requested unless you enable them |
| Input Monitoring / Automation / Calendars / Full Disk | none | Not needed |
| Auto-updater | none | Grants can't be inherited by code you didn't build |
| Dependencies | none | ~750 lines of Swift, Apple frameworks only |
| Private APIs | none | `sandbox_init` is public (deprecated, still supported); `verify.sh` uses `sandbox_check` but only in the separate test tool |

Thumbnails are a single still frame per window, captured only while the preview
is open, held in memory, and released when it closes. Nothing is written to disk or logged
(logs contain counts only, never titles).

## Build

```sh
./build.sh                       # signs with your own "Apple Development" certificate, if you have one
SIGN_IDENTITY=- ./build.sh       # no Apple account needed: ad-hoc signing (permissions reset on every rebuild)
open build/DockPeek.app
```

Requires macOS 14+ and Xcode or the Command Line Tools. Copy `build/DockPeek.app` to `/Applications` if you want to keep it. (Moving it after granting
permissions may require re-granting.)

## Releases

Signed, notarized builds are published on the [Releases](../../releases) page by
`.github/workflows/release.yml` when a `v*` tag is pushed. Each download has a build provenance
attestation, so you can check it was built by this repo's workflow from public source:

```sh
gh attestation verify DockPeek-v0.1.0.zip -R badriram/dockpeek
shasum -a 256 -c SHA256SUMS.txt
```

Maintainers: `scripts/setup-signing.sh` walks through creating the Developer ID certificate and
App Store Connect API key and storing them as secrets in the protected `release` environment.

## Why not the App Sandbox entitlement?

On macOS 27 the App Sandbox blocks Accessibility reads of the Dock (`AXError -25204`) even when
the app is granted access. DockPeek instead applies its own, stricter-on-what-matters sandbox
profile at launch via `sandbox_init`. `APP_SANDBOX=1 ./build.sh` rebuilds with the entitlement to
re-test on future macOS versions.

## Verify it yourself

```sh
./verify.sh    # entitlements, source grep, a self-test that applies the real sandbox profile and
               # attempts each blocked/allowed operation, then a kernel check of the running app
```
Optionally run [LuLu](https://objective-see.org/products/lulu.html): DockPeek should never appear.

## Limitations

- Windows on other Spaces aren't listed (Accessibility only reports the current Space; reaching
  them requires private APIs, which this project avoids).
- Previews appear only for running apps with at least one window.

## License

MIT, see [LICENSE](LICENSE).

#!/bin/bash
# Verifies the running DockPeek is confined: entitlements, then a kernel query of its sandbox.
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-/Applications/DockPeek.app}"
echo "--- entitlements of $APP (expect none) ---"
codesign -d --entitlements - "$APP" 2>/dev/null || true
echo "--- networking code in source (expect nothing) ---"
grep -rnE "URLSession|NWConnection|CFSocket|socket\(|connect\(" Sources/ || echo "  none"
PID=$(pgrep -x DockPeek || true)
[ -z "$PID" ] && { echo "DockPeek is not running"; exit 1; }
mkdir -p build
cc -O -o build/sandbox-check Tools/sandbox-check.c
echo "--- kernel sandbox for running DockPeek ---"
build/sandbox-check "$PID"

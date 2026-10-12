#!/usr/bin/env bash
# Compile and run the data-layer checks in tools/selftest/main.swift against the real sources.
# Nothing touches your Tempo data: every store is pointed at a temporary folder.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
swiftc -swift-version 5 \
    Sources/Activities.swift Sources/JournalStore.swift Sources/SessionStore.swift Sources/Theme.swift \
    tools/selftest/main.swift -o "$TMP/selftest"
"$TMP/selftest" "$TMP"

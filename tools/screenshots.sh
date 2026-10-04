#!/usr/bin/env bash
# Regenerate the README images in docs/ by rendering the real PanelView offscreen.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
mkdir -p docs
SOURCES=$(ls Sources/*.swift | grep -v TempoApp.swift)  # the harness has its own @main
swiftc -swift-version 5 -parse-as-library -D SCREENSHOTS $SOURCES tools/screenshots.swift \
    -o "$TMP/tempo-screenshots"
"$TMP/tempo-screenshots" "$PWD/docs"
defaults delete tempo-screenshots >/dev/null 2>&1 || true
rm -rf "$TMP"

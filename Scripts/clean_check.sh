#!/bin/bash
# Removes files from older Sono builds that clash with this one (safe to re-run).
cd "$(dirname "$0")/.."
for f in Sources/Sono/Core/NavidromeExtras.swift Sources/Sono/UI/Extras.swift; do [ -f "$f" ] && rm -v "$f"; done
rm -rf .build

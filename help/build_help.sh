#!/bin/bash
# Rebuilds the Apple Help Book search index for Sono.
set -e
cd "$(dirname "$0")"

HELP_RES="Sono.help/Contents/Resources/en.lproj"
echo "Indexing Apple Help Book with hiutil..."
hiutil -C -ag -m 3 -s en -f "$HELP_RES/Sono.helpindex" "$HELP_RES"
echo "Help index generated at $HELP_RES/Sono.helpindex"

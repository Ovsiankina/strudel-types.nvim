#!/usr/bin/env bash
# Regenerate lua/strudel-types/sounds.lua: Strudel sound names, drum-machine banks,
# and per-sound preview URLs. GM soundfont names come from the Strudel source; samples,
# banks and URLs come from the sample maps Strudel prebakes (fetched by emit-sounds.mjs).
# Requires: git, node (18+, for global fetch), network.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/lua/strudel-types/sounds.lua"
REPO="${STRUDEL_REPO:-https://codeberg.org/uzu/strudel.git}"

for bin in git node; do
  command -v "$bin" >/dev/null || { echo "strudel-types: '$bin' is required" >&2; exit 1; }
done
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

echo "strudel-types(sounds): cloning $REPO for GM soundfont names..."
git clone --depth 1 "$REPO" "$WORK/src" >/dev/null 2>&1
grep -oE '^[[:space:]]+gm_[a-z0-9_]+:' "$WORK/src/packages/soundfonts/gm.mjs" | tr -d ': ' | sort -u > "$WORK/gm.txt" || true

echo "strudel-types(sounds): fetching sample maps + emitting $OUT..."
node "$ROOT/scripts/emit-sounds.mjs" "$WORK/gm.txt" "$OUT"

echo "strudel-types(sounds): done -> $OUT"

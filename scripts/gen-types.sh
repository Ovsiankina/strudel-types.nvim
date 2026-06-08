#!/usr/bin/env bash
# Regenerate types/strudel.d.ts from Strudel's own JSDoc.
#
# Pipeline: clone Strudel -> run its jsdoc-json step -> doc.json -> scripts/emit.mjs.
# Requires: git, node, npm, and network access. Nothing is installed globally; the
# jsdoc toolchain is fetched into a throwaway temp dir.
#
# Env overrides:
#   STRUDEL_REPO  git URL          (default: codeberg.org/uzu/strudel)
#   STRUDEL_REF   branch/tag        (default: repo default branch)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/types/strudel.d.ts"
REPO="${STRUDEL_REPO:-https://codeberg.org/uzu/strudel.git}"
REF="${STRUDEL_REF:-}"

for bin in git node npm; do
  command -v "$bin" >/dev/null || { echo "strudel-types: '$bin' is required" >&2; exit 1; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "strudel-types: cloning $REPO ${REF:+($REF) }..."
if [ -n "$REF" ]; then
  git clone --depth 1 --branch "$REF" "$REPO" "$WORK/src" >/dev/null 2>&1
else
  git clone --depth 1 "$REPO" "$WORK/src" >/dev/null 2>&1
fi

echo "strudel-types: installing jsdoc toolchain (isolated)..."
( cd "$WORK" && npm init -y >/dev/null 2>&1 \
    && npm i jsdoc@^4 jsdoc-json@^2 --no-audit --no-fund >/dev/null 2>&1 )

echo "strudel-types: extracting JSDoc -> doc.json..."
( cd "$WORK/src" && "$WORK/node_modules/.bin/jsdoc" packages/ \
    --template "$WORK/node_modules/jsdoc-json" \
    --destination "$WORK/doc.json" \
    -c jsdoc/jsdoc.config.json )

echo "strudel-types: emitting $OUT..."
mkdir -p "$ROOT/types"
node "$ROOT/scripts/emit.mjs" "$WORK/doc.json" "$ROOT/scripts/overrides.mjs" > "$OUT"

echo "strudel-types: done -> $OUT"

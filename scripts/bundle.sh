#!/usr/bin/env bash
# Package one assignment into a self-contained submission zip.
#
#   ./scripts/bundle.sh a1-mpc-rec-sys
#   ./scripts/bundle.sh a2-dpf-gen
#   ./scripts/bundle.sh a3-a4-item-update
#   ./scripts/bundle.sh all
#
# Each assignment directory is already standalone (A3 keeps its own adapted
# copies of the A1 protocol and A2 DPF code), so a bundle is just a clean
# export of that directory with build artifacts and OS junk stripped out.

set -euo pipefail
cd "$(dirname "$0")/.."

OUT="bundle"
mkdir -p "$OUT"

bundle_one() {
  local dir="$1"
  [ -d "$dir" ] || { echo "no such assignment: $dir" >&2; return 1; }
  local zip="$OUT/${dir}.zip"
  rm -f "$zip"
  zip -qr "$zip" "$dir" \
      -x '*/.DS_Store' \
      -x '*/.ipynb_checkpoints/*' \
      -x '*.out' -x '*.o' -x "$dir/a" -x "$dir/src/a" \
      -x '*/matrices/*'
  printf '  %-24s -> %s (%s)\n' "$dir" "$zip" "$(du -h "$zip" | cut -f1)"
}

if [ "${1:-all}" = "all" ]; then
  echo "Building all submission bundles:"
  for d in a1-mpc-rec-sys a2-dpf-gen a3-a4-item-update; do bundle_one "$d"; done
else
  echo "Building submission bundle:"
  bundle_one "$1"
fi

#!/usr/bin/env bash
# autosave_loop.sh — every AUTOSAVE_MIN minutes: archive .blend files locally
# and (if an HF token is present) push them to Hugging Face.
# Start with:  nohup bash autosave_loop.sh >> $WORKDIR/blender-env/logs/autosave.log 2>&1 &
WORKDIR="${WORKDIR:-/kaggle/working}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MIN="${AUTOSAVE_MIN:-10}"
ARCHIVE="$WORKDIR/backups"
mkdir -p "$ARCHIVE"
while true; do
  ts="$(date +%Y%m%d-%H%M%S)"
  n=0
  for f in "$WORKDIR"/*.blend; do
    [ -f "$f" ] || continue
    cp -f "$f" "$ARCHIVE/$ts-$(basename "$f")" 2>/dev/null && n=$((n+1))
  done
  echo "[$ts] local archive: $n file(s) → $ARCHIVE"
  if [ -f "$WORKDIR/.hf_token" ]; then
    echo "[$ts] pushing to Hugging Face..."
    WORKDIR="$WORKDIR" bash "$SCRIPT_DIR/backup_to_hf.sh" || echo "  (HF push failed — will retry next cycle)"
  fi
  sleep $((MIN * 60))
done

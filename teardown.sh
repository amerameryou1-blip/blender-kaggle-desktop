#!/usr/bin/env bash
# teardown.sh — stop everything started by launch.sh
set -uo pipefail
WORKDIR="${WORKDIR:-/kaggle/working}"
PID_DIR="$WORKDIR/blender-env/pids"
for n in watch blender cloudflared websockify x11vnc xvfb; do
  p="$PID_DIR/$n.pid"
  if [ -f "$p" ]; then
    kill "$(cat "$p")" >/dev/null 2>&1 && echo "  stopped $n" || echo "  $n already gone"
    rm -f "$p"
  fi
done
pkill -f "cloudflared tunnel" >/dev/null 2>&1 || true
echo "All stopped. Files remain in $WORKDIR"

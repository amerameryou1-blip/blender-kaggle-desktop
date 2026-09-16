#!/usr/bin/env bash
# get_url.sh — print the CURRENT verified phone URL.
# Safe to re-run any time. If cloudflared died or rotated its name, it
# restarts it and captures the fresh URL. Usage:  bash get_url.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env_loader.sh
source "$SCRIPT_DIR/env_loader.sh"
ENV_DIR="${ENV_DIR:-${WORKDIR:-/kaggle/working}/blender-env}"
LOG_DIR="$ENV_DIR/logs"
PID_DIR="$ENV_DIR/pids"
PHONE_PATH="/vnc_lite.html?autoconnect=1&resize=scale&reconnect=1"

start_cloudflared() {
  pkill -f "cloudflared tunnel" >/dev/null 2>&1 || true
  rm -f "$LOG_DIR/cloudflared.log"
  sleep 1
  setsid nohup cloudflared tunnel --url http://127.0.0.1:6080 --no-autoupdate \
    > "$LOG_DIR/cloudflared.log" 2>&1 < /dev/null &
  echo $! > "$PID_DIR/cloudflared.pid"
}

grab() {
  # NEWEST name in the log wins (quick tunnels can re-register under a new name)
  TUNNEL_URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" 2>/dev/null | tail -1 || true)"
  [ -n "$TUNNEL_URL" ] || return 1
  for i in 1 2 3 4 5; do
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 12 "$TUNNEL_URL$PHONE_PATH" 2>/dev/null || echo 000)
    [ "$code" = "200" ] && return 0
    sleep 2
  done
  return 1
}

# 1) is the currently-saved URL still alive?
if [ -f "$ENV_DIR/tunnel.url" ]; then
  CUR="$(cat "$ENV_DIR/tunnel.url")"
  BASE="${CUR%%/vnc_lite*}"
  if [ -f "$PID_DIR/cloudflared.pid" ] && kill -0 "$(cat "$PID_DIR/cloudflared.pid")" 2>/dev/null; then
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 12 "$BASE$PHONE_PATH" 2>/dev/null || echo 000)
    if [ "$code" = "200" ]; then
      echo "$CUR"
      exit 0
    fi
  fi
fi

# 2) try the log URL (cloudflared may have rotated its name)
if [ -f "$PID_DIR/cloudflared.pid" ] && kill -0 "$(cat "$PID_DIR/cloudflared.pid")" 2>/dev/null; then
  if grab; then
    echo "$TUNNEL_URL$PHONE_PATH" | tee "$ENV_DIR/tunnel.url"
    exit 0
  fi
fi

# 3) restart cloudflared and capture a fresh URL
echo "(re)starting cloudflared..." >&2
mkdir -p "$PID_DIR" "$LOG_DIR"
start_cloudflared
for i in $(seq 1 60); do
  if grab; then
    echo "$TUNNEL_URL$PHONE_PATH" | tee "$ENV_DIR/tunnel.url"
    exit 0
  fi
  sleep 1
done
echo "❌ could not get a verified tunnel URL — see $LOG_DIR/cloudflared.log" >&2
exit 1

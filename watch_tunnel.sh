#!/usr/bin/env bash
# watch_tunnel.sh — background self-healer (started by launch.sh, detached).
# Every 45 s: ensure cloudflared is alive and tunnel.url holds a VERIFIED URL.
# If the tunnel rotated its name or died, restart it and update tunnel.url.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env_loader.sh
source "$SCRIPT_DIR/env_loader.sh"
ENV_DIR="${ENV_DIR:-${WORKDIR:-/kaggle/working}/blender-env}"
LOG_DIR="$ENV_DIR/logs"
PID_DIR="$ENV_DIR/pids"
PHONE_PATH="/vnc_lite.html?autoconnect=1&resize=scale&reconnect=1"

while true; do
  alive=0
  [ -f "$PID_DIR/cloudflared.pid" ] && kill -0 "$(cat "$PID_DIR/cloudflared.pid")" 2>/dev/null && alive=1

  if [ "$alive" = "1" ] && [ -f "$ENV_DIR/tunnel.url" ]; then
    BASE="$(head -1 "$ENV_DIR/tunnel.url")"; BASE="${BASE%%/vnc_lite*}"
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 12 "$BASE$PHONE_PATH" 2>/dev/null || echo 000)
    if [ "$code" != "200" ]; then
      echo "[$(date +%H:%M:%S)] saved URL dead — recovering..."
      # the name may have rotated: check the log (NEWEST name wins)
      U="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" 2>/dev/null | tail -1 || true)"
      fixed=0
      if [ -n "$U" ]; then
        for i in 1 2 3; do
          c=$(curl -s -o /dev/null -w "%{http_code}" --max-time 12 "$U$PHONE_PATH" 2>/dev/null || echo 000)
          [ "$c" = "200" ] && { echo "$U$PHONE_PATH" > "$ENV_DIR/tunnel.url"; echo "[$(date +%H:%M:%S)] refreshed to $U"; fixed=1; break; }
          sleep 2
        done
      fi
      if [ "$fixed" != "1" ]; then
        echo "[$(date +%H:%M:%S)] restarting cloudflared..."
        pkill -f "cloudflared tunnel" 2>/dev/null || true
        rm -f "$LOG_DIR/cloudflared.log"; sleep 1
        setsid nohup cloudflared tunnel --url http://127.0.0.1:6080 --no-autoupdate \
          > "$LOG_DIR/cloudflared.log" 2>&1 < /dev/null &
        echo $! > "$PID_DIR/cloudflared.pid"
        for i in $(seq 1 60); do
          U="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" 2>/dev/null | tail -1 || true)"
          if [ -n "$U" ]; then
            for j in 1 2 3 4; do
              c=$(curl -s -o /dev/null -w "%{http_code}" --max-time 12 "$U$PHONE_PATH" 2>/dev/null || echo 000)
              [ "$c" = "200" ] && { echo "$U$PHONE_PATH" > "$ENV_DIR/tunnel.url"; echo "[$(date +%H:%M:%S)] new URL $U"; break 2; }
              sleep 3
            done
          fi
          sleep 1
        done
      fi
    fi
  else
    # cloudflared missing entirely — restart it
    echo "[$(date +%H:%M:%S)] cloudflared not running — starting..."
    mkdir -p "$PID_DIR" "$LOG_DIR"
    rm -f "$LOG_DIR/cloudflared.log"
    setsid nohup cloudflared tunnel --url http://127.0.0.1:6080 --no-autoupdate \
      > "$LOG_DIR/cloudflared.log" 2>&1 < /dev/null &
    echo $! > "$PID_DIR/cloudflared.pid"
  fi
  sleep 45
done

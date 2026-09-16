#!/usr/bin/env bash
# ============================================================================
# launch.sh — start the full stack, fully detached from the notebook kernel:
#   Xvfb (virtual display) → x11vnc (VNC) → noVNC (browser client)
#   → cloudflared (public https URL) → Blender GUI on :99
#
# KEY DETAIL: every service is started with `setsid nohup ... &` so it lives
# in its OWN session — Jupyter kills the cell's process group when the cell
# finishes; plain `&` children would die with it (tunnel URL → NXDOMAIN).
#
# The phone URL (auto-connect + fit-to-screen) is saved to
# $WORKDIR/blender-env/tunnel.url and verified with a real external curl
# before it is printed. A background watcher keeps it alive.
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env_loader.sh
source "$SCRIPT_DIR/env_loader.sh"
WORKDIR="${WORKDIR:-/kaggle/working}"
ENV_DIR="${ENV_DIR:-$WORKDIR/blender-env}"
PID_DIR="$ENV_DIR/pids"
LOG_DIR="$ENV_DIR/logs"
mkdir -p "$PID_DIR" "$LOG_DIR"

# --- helper: start a service fully detached ---------------------------------
detached() {
  # detached NAME CMD...
  local name="$1"; shift
  echo "$name" > "$PID_DIR/$name.starting"
  setsid nohup "$@" > "$LOG_DIR/$name.log" 2>&1 < /dev/null &
  local pid=$!
  echo "$pid" > "$PID_DIR/$name.pid"
  rm -f "$PID_DIR/$name.starting"
}

# --- stop anything we own from a previous launch -----------------------------
for n in blender cloudflared websockify x11vnc xvfb; do
  p="$PID_DIR/$n.pid"
  if [ -f "$p" ]; then
    kill "$(cat "$p")" >/dev/null 2>&1 || true
    rm -f "$p"
  fi
done
pkill -f "cloudflared tunnel" >/dev/null 2>&1 || true
sleep 1

# --- 1. Xvfb (virtual framebuffer, GLX via Mesa) ------------------------------
echo "▶ Starting Xvfb :99 (${RES_W:-1600}x${RES_H:-900})..."
detached xvfb Xvfb :99 -screen 0 "${RES_W:-1600}x${RES_H:-900}x24" -ac \
  +extension GLX +extension RANDR +render
sleep 2
kill -0 "$(cat "$PID_DIR/xvfb.pid")" 2>/dev/null || { echo "❌ Xvfb failed:"; cat "$LOG_DIR/xvfb.log"; exit 1; }
export DISPLAY=:99
# quiet Blender's harmless wayland-probe warning
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/xdg-runtime-$(id -u)}"
mkdir -p "$XDG_RUNTIME_DIR" 2>/dev/null || true

# --- 2. x11vnc (captures the real X display) ---------------------------------
echo "▶ Starting x11vnc on 127.0.0.1:5901..."
detached x11vnc x11vnc -display :99 -forever -shared -nopw -noxdamage \
  -rfbport 5901 -localhost
sleep 1

# --- 3. noVNC / websockify (browser client on 127.0.0.1:6080) ----------------
# Copy noVNC web files into WORKDIR and add an index.html that auto-redirects
# to the mobile client with autoconnect + fit-to-screen. This is what makes
# the BARE tunnel URL open straight into Blender on a phone (no file list).
NOVNC_WEB="$ENV_DIR/novnc-web"
if [ ! -f "$NOVNC_WEB/vnc_lite.html" ]; then
  rm -rf "$NOVNC_WEB"
  for d in /usr/share/noVNC /usr/share/novnc /opt/noVNC; do
    [ -d "$d" ] && cp -r "$d" "$NOVNC_WEB" && break
  done
  [ -f "$NOVNC_WEB/vnc_lite.html" ] || { echo "❌ noVNC web files not found (apt 'novnc' missing?)" >&2; exit 1; }
  cat > "$NOVNC_WEB/index.html" <<'HTML'
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Blender Desktop</title>
  <meta http-equiv="refresh" content="0; url=/vnc_lite.html?autoconnect=1&resize=scale&reconnect=1">
</head>
<body style="background:#0b0a08;color:#c9a24b;font-family:sans-serif;padding:24px">
  Opening Blender desktop…
  <a style="color:#e9cd8a" href="/vnc_lite.html?autoconnect=1&resize=scale&reconnect=1">
  (if not redirected, tap here)</a>
</body>
</html>
HTML
  echo "  ✔ noVNC web root prepared (auto-redirect landing page)"
fi
echo "▶ Starting noVNC (websockify) on 127.0.0.1:6080..."
if command -v websockify >/dev/null 2>&1; then
  detached websockify websockify --web "$NOVNC_WEB" 6080 localhost:5901
else
  detached websockify python3 -m websockify --web "$NOVNC_WEB" 6080 localhost:5901
fi
sleep 1

# --- 4. cloudflared quick tunnel (public URL, no account needed) -------------
PHONE_PATH="/vnc_lite.html?autoconnect=1&resize=scale&reconnect=1"

start_cloudflared() {
  pkill -f "cloudflared tunnel" >/dev/null 2>&1 || true
  rm -f "$LOG_DIR/cloudflared.log"
  sleep 1
  detached cloudflared cloudflared tunnel --url http://127.0.0.1:6080 --no-autoupdate
}

verify_url() {
  # $1 = bare https URL → returns 0 if the VNC client is reachable through it
  local base="$1"
  for i in 1 2 3 4 5; do
    local code
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 12 "$base$PHONE_PATH" 2>/dev/null || echo 000)
    [ "$code" = "200" ] && return 0
    sleep 2
  done
  return 1
}

echo "▶ Starting cloudflared quick tunnel (takes ~5-15 s)..."
start_cloudflared
TUNNEL_URL=""
for i in $(seq 1 45); do
  TUNNEL_URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" 2>/dev/null | tail -1 || true)"
  [ -n "$TUNNEL_URL" ] && break
  sleep 1
done

if [ -z "$TUNNEL_URL" ]; then
  echo "⚠ cloudflared did not return a URL in 45 s. Log tail:"
  tail -5 "$LOG_DIR/cloudflared.log" 2>/dev/null || true
else
  # verify BEFORE trusting it; restart cloudflared a couple of times if needed
  ok=0
  for attempt in 1 2 3; do
    if verify_url "$TUNNEL_URL"; then ok=1; break; fi
    echo "  ⚠ URL not answering yet (attempt $attempt) — restarting cloudflared..."
    sleep 3
    start_cloudflared
    TUNNEL_URL=""
    for i in $(seq 1 45); do
      TUNNEL_URL="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_DIR/cloudflared.log" 2>/dev/null | tail -1 || true)"
      [ -n "$TUNNEL_URL" ] && break
      sleep 1
    done
    [ -n "$TUNNEL_URL" ] || break
  done
  if [ "$ok" = "1" ]; then
    echo "$TUNNEL_URL$PHONE_PATH" > "$ENV_DIR/tunnel.url"
    echo "  ✔ tunnel URL verified end-to-end"
  else
    echo "❌ tunnel URL could not be verified — check log: $LOG_DIR/cloudflared.log"
    echo "$TUNNEL_URL$PHONE_PATH" > "$ENV_DIR/tunnel.url"
  fi
fi

# --- 5. Blender GUI ------------------------------------------------------------
echo "▶ Starting Blender (Cycles auto-configured)..."
detached blender "$BLENDER_BIN" --python "$SCRIPT_DIR/startup_blender.py"
sleep 3

# --- 6. background watcher (keeps tunnel.url fresh, restarts cloudflared) -----
if [ -f "$SCRIPT_DIR/watch_tunnel.sh" ]; then
  setsid nohup bash "$SCRIPT_DIR/watch_tunnel.sh" >> "$LOG_DIR/watch.log" 2>&1 < /dev/null &
  echo $! > "$PID_DIR/watch.pid"
  echo "  ✔ tunnel watcher started (self-healing URL)"
fi

# --- status ---------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  STACK STATUS"
echo "────────────────────────────────────────────────────────────────"
for n in xvfb x11vnc websockify cloudflared blender; do
  if [ -f "$PID_DIR/$n.pid" ] && kill -0 "$(cat "$PID_DIR/$n.pid")" 2>/dev/null; then
    echo "  ✔ $n (pid $(cat "$PID_DIR/$n.pid"))"
  else
    echo "  ✖ $n NOT RUNNING — see $LOG_DIR/$n.log"
  fi
done
echo "────────────────────────────────────────────────────────────────"
echo ""
echo "  📱 OPEN THIS ON YOUR PHONE (Chrome/Edge, landscape, full screen):"
echo "     Auto-connects and fits the screen. Tap once to send clicks."
echo ""
echo "      $(cat "$ENV_DIR/tunnel.url" 2>/dev/null || echo '(no URL — check cloudflared.log)')"
echo ""
echo "  If a URL ever stops working:  bash $SCRIPT_DIR/get_url.sh"
echo "════════════════════════════════════════════════════════════════"
echo "  Logs: $LOG_DIR   (stop everything: bash teardown.sh)"

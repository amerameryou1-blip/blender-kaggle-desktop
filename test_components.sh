#!/usr/bin/env bash
# test_components.sh — verify every part of the stack. Prints PASS/FAIL lines.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env_loader.sh
source "$SCRIPT_DIR/env_loader.sh"
ENV_DIR="${ENV_DIR:-${WORKDIR:-/kaggle/working}/blender-env}"
LOGS="$ENV_DIR/logs"
PASS=0; FAIL=0; WARN=0
ok()   { echo "  ✔ PASS  $1"; PASS=$((PASS+1)); }
bad()  { echo "  ✖ FAIL  $1"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠ WARN  $1"; WARN=$((WARN+1)); }

echo "═══ component tests ═══"

# 1. architecture
[ "$(uname -m)" = "x86_64" ] && ok "architecture x86_64" || warn "architecture $(uname -m) (Kaggle should be x86_64)"

# 2. GPU
if command -v nvidia-smi >/dev/null 2>&1; then
  NGPU=$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l)
  ok "GPU: $NGPU device(s) — $(nvidia-smi --query-gpu=name --format=csv,noheader | paste -sd ', ')"
else
  warn "no nvidia-smi → CPU-only mode (normal for CPU notebooks / this sandbox)"
fi

# 3. Xvfb
if [ -f "$ENV_DIR/pids/xvfb.pid" ] && kill -0 "$(cat "$ENV_DIR/pids/xvfb.pid")" 2>/dev/null; then
  ok "Xvfb :99 running"
  if DISPLAY=:99 xdotool getdisplaygeometry >/dev/null 2>&1; then
    ok "X display answers — $(DISPLAY=:99 xdotool getdisplaygeometry)"
  else
    bad "X display not answering"
  fi
else
  bad "Xvfb not running (run launch.sh)"
fi

# 4. x11vnc — real RFB protocol handshake
if python3 - <<'PY' 2>/dev/null
import socket, sys
s = socket.create_connection(("127.0.0.1", 5901), timeout=5)
banner = s.recv(12).decode("ascii", "replace").strip()
sys.exit(0 if banner.startswith("RFB 003") else 1)
PY
then ok "x11vnc: RFB handshake OK"; else bad "x11vnc: no RFB handshake on :5901"; fi

# 5. noVNC (root must redirect to the client — what phones hit)
CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1:6080/vnc.html || echo 000)
[ "$CODE" = "200" ] && ok "noVNC serving /vnc.html (200)" || bad "noVNC not serving (HTTP $CODE)"
ROOT_BODY=$(curl -s --max-time 5 http://127.0.0.1:6080/ || true)
echo "$ROOT_BODY" | grep -q "vnc_lite.html" && ok "noVNC root auto-redirects to VNC client" || bad "noVNC root does NOT redirect (phones would see a file list)"

# 6. cloudflared tunnel (test the BARE URL, exactly what the phone opens)
if [ -f "$ENV_DIR/tunnel.url" ]; then
  U=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$ENV_DIR/tunnel.url" | head -1)
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 15 "$U/" || echo 000)
  CODE2=$(curl -s --max-time 15 "$U/vnc_lite.html" | grep -c "VNC" || echo 0)
  if [ "$CODE" = "200" ] && [ "$CODE2" -gt 0 ]; then
    ok "public tunnel: bare URL + VNC client both live ($U/)"
  else
    bad "public tunnel not answering (root HTTP $CODE, client hits $CODE2): $U"
  fi
else
  warn "no tunnel.url yet (cloudflared still starting? re-run launch.sh)"
fi

# 7. Blender binary
if [ -x "${BLENDER_BIN:-}" ]; then
  V=$("$BLENDER_BIN" --version 2>/dev/null | head -1)
  ok "Blender: $V"
else
  bad "Blender binary not found (run setup.sh)"
fi

echo "════════════════════════"
echo "  $PASS passed, $FAIL failed, $WARN warnings"
[ "$FAIL" -eq 0 ]

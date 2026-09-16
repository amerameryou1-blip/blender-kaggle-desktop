#!/usr/bin/env bash
# run_render_test.sh — headless Cycles smoke test (GPU or CPU, auto)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=env_loader.sh
source "$SCRIPT_DIR/env_loader.sh"
echo "▶ Running headless Cycles render test..."
WORKDIR="${WORKDIR:-/kaggle/working}" "$BLENDER_BIN" --background --python "$SCRIPT_DIR/render_test.py"
echo ""
echo "✔ Test render saved to ${WORKDIR}/test-render.png"

#!/usr/bin/env bash
# ============================================================================
# setup.sh — one-shot installer for the Blender-on-Kaggle desktop
#
# Idempotent: safe to re-run. Caches Blender + cloudflared in $WORKDIR so
# re-running a Kaggle notebook that has the previous output dataset attached
# skips the big downloads.
#
# Env overrides:
#   WORKDIR        (default /kaggle/working; fallback $HOME/blender-work)
#   BLENDER_VERSION (force a specific version, e.g. 4.5.0)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="${WORKDIR:-/kaggle/working}"
if [ ! -d "$WORKDIR" ]; then
  mkdir -p "$WORKDIR" 2>/dev/null || WORKDIR="${HOME}/blender-work"
fi
if [ ! -w "$WORKDIR" ]; then
  echo "❌ $WORKDIR is not writable; falling back to ${HOME}/blender-work" >&2
  WORKDIR="${HOME}/blender-work"
fi
mkdir -p "$WORKDIR"
echo "▶ Working dir: $WORKDIR"

# ----------------------------------------------------------------------------
# 0. Architecture check (Kaggle is x86_64 Linux)
# ----------------------------------------------------------------------------
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) BL_ARCH="x64" ;;
  aarch64|arm64)
    echo "❌ ARM64 host detected. Kaggle GPU notebooks are x86_64 — if you really" >&2
    echo "   are on ARM there is no official 64-bit ARM Blender tarball; use a" >&2
    echo "   Kaggle x86_64 instance instead." >&2
    exit 1
    ;;
  *) echo "❌ Unsupported architecture: $ARCH" >&2; exit 1 ;;
esac
echo "▶ Architecture: $ARCH → Blender linux-$BL_ARCH build"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then SUDO="sudo"; fi

# ----------------------------------------------------------------------------
# 1. Connectivity check
# ----------------------------------------------------------------------------
echo "▶ Checking internet access..."
if ! curl -sI --max-time 15 https://github.com | head -1 | grep -q " 200"; then
  echo "❌ No internet access from this notebook." >&2
  echo "   Kaggle → Kernel settings (⚙ top right) → enable 'Internet' → Re-run." >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# 2. apt packages (virtual X + VNC + noVNC + X11 libs Blender needs)
# ----------------------------------------------------------------------------
PKGS="xvfb x11vnc novnc websockify xdotool mesa-utils scrot
  libgl1 libgl1-mesa-dri
  libx11-6 libx11-xcb1 libx11-xcb1 libxcursor1 libxfixes3 libxi6 libxrender1
  libxrandr2 libxext6 libxkbcommon0 libxkbcommon-x11-0 libsm6 libice6
  libfontconfig1 libfreetype6 libdbus-1-3 libpng16-16
  fonts-dejavu-core fonts-dejavu-extra"

missing=0
for p in $PKGS; do dpkg -s "$p" >/dev/null 2>&1 || missing=1; done
if [ "$missing" -eq 1 ]; then
  echo "▶ Installing X/VNC packages via apt (first run only)..."
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq $PKGS >/dev/null
  echo "  ✔ apt packages installed"
else
  echo "  ✔ apt packages already present"
fi
# websockify fallback via python module
command -v websockify >/dev/null 2>&1 || pip install -q websockify

# ----------------------------------------------------------------------------
# 3. GPU detection (T4 / P100 / none) — drives Cycles config + LD_LIBRARY_PATH
# ----------------------------------------------------------------------------
ENV_DIR="$WORKDIR/blender-env"
mkdir -p "$ENV_DIR"
echo "▶ Detecting GPUs..."
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi --query-gpu=index,name,memory.total,driver_version --format=csv > "$ENV_DIR/gpu.info" 2>/dev/null || true
  NGPU="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | wc -l)"
  echo "  ✔ $NGPU GPU(s) detected:"
  sed 's/^/      /' "$ENV_DIR/gpu.info"
else
  echo "⚠ No nvidia-smi → CPU-only mode (Blender runs, Cycles renders on CPU)."
  echo "no-GPU" > "$ENV_DIR/gpu.info"
fi

NVIDIA_LIBDIRS=""
for d in /usr/local/nvidia/lib64 /usr/local/cuda/lib64 /usr/lib/x86_64-linux-gnu; do
  if [ -d "$d" ] && ls "$d"/libcuda* >/dev/null 2>&1; then NVIDIA_LIBDIRS="$NVIDIA_LIBDIRS:$d"; fi
done

# ----------------------------------------------------------------------------
# 4. cloudflared (public tunnel so your phone can reach the notebook)
# ----------------------------------------------------------------------------
CACHE_BIN="$WORKDIR/.cache/bin"
mkdir -p "$CACHE_BIN"
if [ ! -x "$CACHE_BIN/cloudflared" ]; then
  echo "▶ Downloading cloudflared (latest)..."
  URL="$(curl -s https://api.github.com/repos/cloudflare/cloudflared/releases/latest \
        | grep -oE '"browser_download_url": *"[^"]*linux-amd64[^"]*"' | head -1 \
        | sed 's/.*: *"//; s/"$//')"
  if [ -z "$URL" ]; then
    URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
  fi
  curl -sL "$URL" -o "$CACHE_BIN/cloudflared"
  chmod +x "$CACHE_BIN/cloudflared"
fi
"$CACHE_BIN/cloudflared" --version | head -1 | sed 's/^/  ✔ /'

# ----------------------------------------------------------------------------
# 5. Blender (official Linux x64 tarball, version auto-detected, cached)
# ----------------------------------------------------------------------------
BL_DIR="$WORKDIR/blender"
# 5a) fast path: tarball already present (fetched from the HF hub dataset)
LOCAL_TB="$(ls "$SCRIPT_DIR"/blender-*.tar.xz "$WORKDIR"/blender-*.tar.xz 2>/dev/null | head -1 || true)"
if [ -x "$BL_DIR/blender" ] && [ -f "$WORKDIR/.blender_version" ]; then
  echo "  ✔ Blender already cached: $(cat "$WORKDIR/.blender_version")"
elif [ -n "$LOCAL_TB" ]; then
  VER="$(basename "$LOCAL_TB" | sed -E 's/^blender-([0-9.]+)-linux-.*/\1/')"
  echo "▶ Using local Blender tarball (from HF hub): $(basename "$LOCAL_TB")"
  rm -rf "$BL_DIR"
  tar -xf "$LOCAL_TB" -C "$WORKDIR"
  mv "$WORKDIR/blender-$VER-linux-$BL_ARCH" "$BL_DIR"
  echo "$VER" > "$WORKDIR/.blender_version"
  echo "  ✔ Blender $VER installed from local tarball"
else
  # version discovery: pinned list (newest first), then parse the download page
  if [ -n "${BLENDER_VERSION:-}" ]; then
    VER="$BLENDER_VERSION"
  else
    VER=""
    for v in 4.5.2 4.5.1 4.5.0 4.4.2 4.4.1 4.4.0 4.3.2 4.3.1 4.3.0 4.2.3 4.2.2 4.2.0 4.1.2 4.1.0 4.0.4; do
      if curl -sI --max-time 10 "https://download.blender.org/release/Blender$(echo "$v" | cut -d. -f1,2)/blender-$v-linux-$BL_ARCH.tar.xz" | head -1 | grep -q " 200"; then
        VER="$v"; break
      fi
    done
    if [ -z "$VER" ]; then
      VER="$(curl -s --max-time 20 https://www.blender.org/download/ | grep -oE 'Blender[0-9]+\.[0-9]+\.[0-9]+' | head -1 | sed 's/Blender//')"
    fi
    if [ -z "$VER" ]; then
      echo "❌ Could not determine a Blender download URL. Set BLENDER_VERSION and re-run." >&2
      exit 1
    fi
  fi
  MAJOR="$(echo "$VER" | cut -d. -f1,2)"
  TARBALL="blender-$VER-linux-$BL_ARCH.tar.xz"
  echo "▶ Downloading Blender $VER ($TARBALL, ~350 MB) — first run only..."
  curl -fL --retry 3 "https://download.blender.org/release/Blender$MAJOR/$TARBALL" -o "$WORKDIR/$TARBALL"
  echo "▶ Extracting..."
  rm -rf "$BL_DIR"
  tar -xf "$WORKDIR/$TARBALL" -C "$WORKDIR"
  mv "$WORKDIR/blender-$VER-linux-$BL_ARCH" "$BL_DIR"
  rm -f "$WORKDIR/$TARBALL"
  echo "$VER" > "$WORKDIR/.blender_version"
  echo "  ✔ Blender $VER installed at $BL_DIR"
fi
"$BL_DIR/blender" --version | head -1 | sed 's/^/  ✔ /'

# ----------------------------------------------------------------------------
# 6. Environment file used by launch.sh
# ----------------------------------------------------------------------------
cat > "$ENV_DIR/env.sh" <<EOF
export DISPLAY=:99
export WORKDIR="$WORKDIR"
export BLENDER_BIN="$BL_DIR/blender"
export ENV_DIR="$ENV_DIR"
export RES_W="\${RES_W:-1600}"
export RES_H="\${RES_H:-900}"
[ -n "$NVIDIA_LIBDIRS" ] && export LD_LIBRARY_PATH="${NVIDIA_LIBDIRS#}:\$LD_LIBRARY_PATH"
export PATH="$CACHE_BIN:\$PATH"
EOF
echo "✅ Setup complete. Run: bash launch.sh"

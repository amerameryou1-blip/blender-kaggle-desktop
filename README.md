# 🎨 Blender Desktop on Kaggle — from your Android phone

Run the **full Blender GUI** on a Kaggle Linux notebook (Kaggle CPU + GPU do the
work) and control it remotely from any Android phone — no PC needed.

```
┌──────────────────┐   public https URL    ┌────────────────────────────────────────────┐
│  Android phone   │ ────────────────────▶ │  Kaggle notebook (Linux x86_64 + T4/P100)  │
│  Chrome / Edge   │   (Cloudflare quick   │                                            │
│  → noVNC web UI  │    tunnel, cloudflared)│  Blender GUI ──▶ Xvfb :99 (virtual X)     │
└──────────────────┘                       │        ▲                        │         │
                                           │        │ renders to             ▼         │
                                           │  Cycles GPU (OptiX/CUDA, N GPUs) x11vnc   │
                                           │                              (VNC :5901)  │
                                           │                                             │
                                           │  noVNC/websockify (:6080) ◀────────────────┘
                                           │  /kaggle/working  ← your .blend files + backups
                                           └────────────────────────────────────────────┘
```

## How it works (and the honest trade-offs)

| Part | Runs on | Notes |
|---|---|---|
| Blender **viewport** (what you see) | Xvfb + **Mesa llvmpipe (CPU software GL)** | Xvfb has no GPU access, so the viewport renders on CPU. Fine for modeling at 1600×900. Use **Solid** shading for best phone responsiveness. |
| **Cycles rendering** | **GPU (OptiX → CUDA)** — all detected GPUs | T4 (7.5) & P100 (6.0) both supported by official builds. 2× T4 → both enabled (Cycles multi-GPU). No SLI/vulkan-style combining for the *viewport* — only for Cycles/EEVEE compute. |
| Remote view | x11vnc → noVNC → **cloudflared quick tunnel** | Public random `*.trycloudflare.com` URL, no account, no exposed Kaggle ports. Session-lifetime only. |
| Persistence | `/kaggle/working` + optional Hugging Face mirror | Kaggle sessions are temporary; `/kaggle/working` becomes an output dataset, and the autosave loop can push every `.blend` to HF. |

**Security note:** the tunnel URL is unguessable but anyone who has it can see
your Blender. It dies with the session. If you need auth, put an nginx
auth_basic or a WireGuard tunnel in front (out of scope here).

## Quick start (Kaggle)

1. **New Notebook** → set **GPU: T4** (optional but recommended) and
   **Internet: On** (required).
2. Paste `notebook.ipynb` → **Cell 1** (or clone this repo into Kaggle and run).
3. First run takes ~3–6 min (apt packages + ~350 MB Blender download; cached
   for the session).
4. It prints a `https://xxxx.trycloudflare.com` URL → **open it on your phone**.
5. Run **Cell 2** (component tests) and **Cell 3** (GPU render smoke test).

### The 3-line copy-paste (if you don't use the .ipynb)

```python
!rm -rf /kaggle/working/blender-kaggle && git clone --depth 1 https://github.com/amerameryou1-blip/blender-kaggle-desktop.git /kaggle/working/blender-kaggle
!cd /kaggle/working/blender-kaggle && WORKDIR=/kaggle/working bash setup.sh && WORKDIR=/kaggle/working bash launch.sh
!cat /kaggle/working/blender-env/tunnel.url
```

## Connecting from Android (Xiaomi Redmi Note 14 Pro 4G / any Android)

1. Chrome/Edge → paste the tunnel URL → VNC screen → **Connect** (no password by default).
2. **Landscape** + fullscreen (⤢) + tap once so input reaches Blender.
3. Chrome ⋮ → *Add to Home screen* for an app-like launcher icon.
4. **Touch mapping (noVNC):** one finger = left mouse drag (orbit/move).
   **No mouse wheel** — zoom with the viewport toolbar (magnifier +/−, ⌂ frame),
   pan with the 2D-pan arrows or `SHIFT+middle`-equivalent via keyboard layout.
   Menus: tap. For more precision use the noVNC toolbar (top-right of the page).

## What's in the repo

| File | Purpose |
|---|---|
| `notebook.ipynb` | The full Kaggle notebook (5 cells + instructions) |
| `setup.sh` | Idempotent installer: arch check, apt (xvfb/x11vnc/novnc/websockify/X11 libs), GPU detect, cloudflared + Blender (version auto-detect, cached) |
| `launch.sh` | Starts Xvfb → x11vnc → noVNC → cloudflared → Blender; prints + saves the phone URL |
| `startup_blender.py` | Blender `--python` startup config: Cycles backend **OptiX → CUDA → CPU**, all GPUs on, prints device summary |
| `render_test.py` / `run_render_test.sh` | Headless Cycles smoke test → `/kaggle/working/test-render.png` |
| `test_components.sh` | PASS/FAIL check of every component incl. a real RFB handshake |
| `backup_to_hf.sh` | Push all `.blend` to a HF dataset (`<user>/blender-backups`) |
| `autosave_loop.sh` | Every 10 min: local archive + HF push (if token set) |
| `teardown.sh` | Stop everything cleanly |

## GPU notes (read this)

- **1× or 2× T4, or 1× P100:** all supported. Cycles renders on **all** enabled
  GPUs (real multi-GPU). `startup_blender.py` prefers **OptiX** (fastest on both
  Turing and Volta with a recent driver) and falls back to **CUDA**, then CPU.
- **Kaggle driver quirk:** if Cycles reports no GPU devices even though
  `nvidia-smi` works, `setup.sh` already adds `/usr/local/nvidia/lib64` to
  `LD_LIBRARY_PATH` (see `blender-env/env.sh`). Re-run `launch.sh`.
- **Viewport ≠ render:** the viewport you see over VNC is CPU software GL.
  "Cycles" *viewport shading* will still compute on GPU but display through the
  software GL pipeline — for phone use, model in **Solid**, hit **Render (F12)**
  for GPU results (save renders to `/kaggle/working`).
- Multi-GPU ≠ 2× speed everywhere: Cycles partitions work across GPUs, but
  viewports, geometry booleans, sculpting etc. stay single-core/CPU.

## Persistence strategy (Hugging Face is your storage)

| What | Where | Notes |
|---|---|---|
| Setup scripts + Blender 4.5.2 tarball (377 MB) | **`amer21/blender-kaggle-hub`** (public dataset) | The notebook fetches everything from here first — no blender.org download, works on any Kaggle session |
| Your `.blend` files | **`amer21/blender-backups`** (private dataset) | Cell 4 + autosave loop push every version every 10 min |
| During a session | `/kaggle/working` | Normal Blender Save As; also becomes the notebook output dataset |
| Local archive | `/kaggle/working/backups/` | Timestamped copies of every `.blend` |
| Code mirror | GitHub `amerameryou1-blip/blender-kaggle-desktop` | Fallback fetch source if HF is down |

To update the hub (after editing scripts): push to GitHub, then re-upload the
changed files to `amer21/blender-kaggle-hub` (one `upload_file` call per file).

## Troubleshooting

| Symptom | Fix |
|---|---|
| Phone shows a **directory listing** (app/, core/, vnc.html…) | The tunnel is alive — you just hit noVNC's root. Use the full URL printed by `launch.sh` (ends with `/vnc_lite.html?autoconnect=1…`), or re-run `launch.sh` (newer builds add an auto-redirect landing page, so even the bare URL works) |
| VNC screen is black after connecting | Blender still starting — wait 10–20 s; check `blender-env/logs/blender.log` |
| Viewport doesn't fit the phone | Make sure the URL contains `resize=scale` (all URLs printed since the 2026-09-16 fix do) |
| Cell 1 says "No internet" | Kernel settings ⚙ → Internet: **On** → Re-run |
| Tunnel URL never printed | Retry Cell 1 (cloudflared is rate-limited at times); check `blender-env/logs/cloudflared.log` |
| `Cycles backend: CPU` on a GPU notebook | Check `nvidia-smi` runs in a cell; re-run `launch.sh` (LD_LIBRARY_PATH fix); look at the printed device summary |
| Viewport is sluggish on phone | Lower resolution: edit `RES_W=1280 RES_H=720` in `blender-env/env.sh`, re-run `launch.sh`; use Solid shading |
| `apt` fails on Kaggle | Rare; re-run Cell 1 (idempotent) |
| Blender crash on start | `cat /kaggle/working/blender-env/logs/blender.log` — most often OOM on 16 GB T4 with huge scenes |

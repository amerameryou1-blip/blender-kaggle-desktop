#!/usr/bin/env bash
# backup_to_hf.sh — push every .blend in $WORKDIR to Hugging Face (dataset repo).
# Needs HF_TOKEN (env) or $WORKDIR/.hf_token. Optional: HF_REPO_ID (default <user>/blender-backups)
set -euo pipefail
WORKDIR="${WORKDIR:-/kaggle/working}"
TOK="${HF_TOKEN:-}"
[ -z "$TOK" ] && [ -f "$WORKDIR/.hf_token" ] && TOK="$(cat "$WORKDIR/.hf_token")"
if [ -z "$TOK" ]; then
  echo "⚠ No HF token (set HF_TOKEN or $WORKDIR/.hf_token) — backup skipped."
  exit 0
fi
pip install -q huggingface_hub 2>/dev/null || true
export HF_TOKEN="$TOK"
python3 - "$WORKDIR" <<'PY'
import glob, os, sys, time
from huggingface_hub import HfApi

work = sys.argv[1]
api = HfApi()
me = api.whoami()["name"]
repo = os.environ.get("HF_REPO_ID", f"{me}/blender-backups")
api.create_repo(repo_id=repo, repo_type="dataset", exist_ok=True, private=False)
files = sorted(glob.glob(os.path.join(work, "*.blend")))
ts = time.strftime("%Y%m%d-%H%M%S")
if not files:
    print("No .blend files in", work)
    sys.exit(0)
for f in files:
    dest = f"{ts}-{os.path.basename(f)}"
    api.upload_file(path_or_fileobj=f, path_in_repo=dest, repo_id=repo, repo_type="dataset")
    print("  ✔ uploaded", dest, f"({os.path.getsize(f)/1048576:.1f} MB)")
print(f"Repo: https://huggingface.co/datasets/{repo}")
PY

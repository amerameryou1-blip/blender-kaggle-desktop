# publish_status.py — publish the current live status to the HF hub.
# Written by the live kernel to: amer21/blender-backups/live-status.json
# (so the phone URL is reachable at a STABLE address, even if the tunnel
#  rotates its random trycloudflare name)
import json
import os
import subprocess
import time

WORK = os.environ.get("WORKDIR", "/kaggle/working")
REPO = "amer21/blender-backups"
HF_TOKEN = os.environ.get("HF_TOKEN", "")
if not HF_TOKEN and os.path.exists(WORK + "/.hf_token"):
    HF_TOKEN = open(WORK + "/.hf_token").read().strip()

def curl_status(url, tries=3):
    for i in range(tries):
        try:
            code = subprocess.run(
                ['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', '--max-time', '15', url],
                capture_output=True, text=True).stdout.strip()
            if code == "200":
                return "200"
        except Exception:
            pass
        time.sleep(2)
    return "unreachable"

def main():
    from huggingface_hub import HfApi
    api = HfApi(token=HF_TOKEN)

    url = ""
    p = WORK + "/blender-env/tunnel.url"
    if os.path.exists(p):
        url = open(p).read().strip()
    base = url.split("/vnc_lite")[0]

    dev = ""
    logp = WORK + "/blender-env/logs/blender.log"
    if os.path.exists(logp):
        log = open(logp, errors="replace").read()
        i = log.find("Cycles compute backend")
        if i >= 0:
            dev = log[max(0, i - 40):i + 320]

    status = {
        "url": url,
        "external_check": curl_status(url) if url else "no-url",
        "device_summary": dev.strip(),
        "updated_utc": time.strftime("%Y-%m-%d %H:%M:%S", time.gmtime()),
    }
    payload = json.dumps(status, indent=2)
    with open(WORK + "/live-status.json", "w") as f:
        f.write(payload)

    api.upload_file(path_or_fileobj=WORK + "/live-status.json",
                    path_in_repo="live-status.json", repo_id=REPO, repo_type="dataset")

    # STABLE PHONE LINK — public, never changes, always redirects to the live tunnel
    if url:
        html = ("<!doctype html><html><head><meta charset=\"utf-8\">"
                "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
                "<title>Blender Desktop</title>"
                "<meta http-equiv=\"refresh\" content=\"0; url=" + url + "\">"
                "<style>body{background:#0b0a08;color:#e9cd8a;font-family:sans-serif;"
                "display:flex;align-items:center;justify-content:center;height:100vh;margin:0}"
                "a{background:#c9a24b;color:#0b0a08;font-size:22px;font-weight:bold;"
                "padding:18px 34px;border-radius:12px;text-decoration:none;display:block;text-align:center}"
                "small{color:#777}</style>"
                "</head><body><div style='text-align:center'>Opening Blender desktop…<br><br>"
                "<a href=\"" + url + "\">🎨 OPEN BLENDER (tap if stuck)</a><br><br>"
                "<small>If the screen stays blank, tap Reload once.</small></div></body></html>")
        with open(WORK + "/phone.html", "w") as f:
            f.write(html)
        api.upload_file(path_or_fileobj=WORK + "/phone.html", path_in_repo="phone.html",
                        repo_id="amer21/blender-kaggle-hub", repo_type="dataset")
        print("📲 stable phone link → https://huggingface.co/datasets/amer21/blender-kaggle-hub/resolve/main/phone.html")

    print("📡 live status → https://huggingface.co/datasets/amer21/blender-backups/resolve/main/live-status.json")
    print(payload)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("publish_status failed:", e)

"""Parallel ranged download of Zenodo MM-Fit rgb videos + md5 check against the Zenodo record. usage: pdl.py w20 w19 ..."""
import hashlib, json, os, subprocess, sys, urllib.request
from concurrent.futures import ThreadPoolExecutor
rec = json.load(urllib.request.urlopen("https://zenodo.org/api/records/7672767"))
files = {f["key"]: f for f in rec["files"]}
N = 24
for w in sys.argv[1:]:
    f = files[f"{w}_rgb.mp4"]; size = f["size"]; out = f"rgb/{w}_rgb.mp4"
    url = f"https://zenodo.org/api/records/7672767/files/{w}_rgb.mp4/content"
    step = -(-size // N); parts = [(i, i * step, min(size, (i + 1) * step) - 1) for i in range(N)]
    def get(p):
        i, a, b = p; part = f"{out}.p{i:02d}"
        for _ in range(60):
            have = os.path.getsize(part) if os.path.exists(part) else 0
            if have == b - a + 1: return
            if have > b - a + 1: raise RuntimeError(f"overrun {part}")
            subprocess.run(["curl", "-sL", "--max-time", "1800", "-r", f"{a + have}-{b}", url, "-o", "-"], stdout=open(part, "ab"))
        raise RuntimeError(part)
    with ThreadPoolExecutor(N) as ex: list(ex.map(get, parts))
    h = hashlib.md5()
    with open(out, "wb") as o:
        for i, _, _ in parts:
            d = open(f"{out}.p{i:02d}", "rb").read(); h.update(d); o.write(d)
    ok = "md5:" + h.hexdigest() == f["checksum"]
    print(w, size, h.hexdigest(), "OK" if ok else "MISMATCH", flush=True)
    if ok:
        for i, _, _ in parts: os.remove(f"{out}.p{i:02d}")

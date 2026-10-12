"""Search YouTube with the Creative Commons filter and keep only videos whose own licence field is CC BY.

Conda env bpt-data (yt-dlp; YTDLP=<path>). Home's IP got the YouTube bot check, so run it on the Mac. Evaluation use only (non-commercial capstone).
usage: python -I yt_cc_search.py <out.tsv> [query ...]
Step 1: CC-filtered search (sp=EgIwAQ==) per query, flat list. Step 2: full metadata per hit;
keep license containing "Creative Commons". Writes id, channel, channel_id, license, duration, height, title, query.
"""
import csv, json, os, subprocess, sys, urllib.parse
from concurrent.futures import ThreadPoolExecutor

YTDLP = os.environ.get("YTDLP", "yt-dlp")
JS = ["--js-runtimes", "node"]  # needed by recent yt-dlp for YouTube
CC = "EgIwAQ%3D%3D"  # YouTube search filter "Creative Commons"
QUERIES = [
    "squat form", "squat mistakes", "squat common mistakes", "how to squat", "bodyweight squat",
    "back squat", "goblet squat", "air squat", "squat technique", "squat side view", "squat knee valgus",
    "push up form", "push up mistakes", "push up common mistakes", "how to do a push up", "pushups",
    "push-up technique", "push up side view", "proper push up",
    "barbell row", "bent over row", "bent over row form", "barbell row mistakes", "pendlay row",
    "dumbbell bent over row", "how to barbell row",
]
KEEP = ("squat", "push", "row")


def search(q, n=60):
    url = f"https://www.youtube.com/results?search_query={urllib.parse.quote_plus(q)}&sp={CC}"
    r = subprocess.run([YTDLP, *JS, "--flat-playlist", "--playlist-end", str(n), "-J", url], capture_output=True, text=True)
    return [(e["id"], q) for e in json.loads(r.stdout or "{}").get("entries", []) if e.get("id")]


def meta(vid):
    r = subprocess.run([YTDLP, *JS, "--skip-download", "-J", f"https://www.youtube.com/watch?v={vid}"], capture_output=True, text=True)
    return json.loads(r.stdout) if r.returncode == 0 else None


def main(out, *queries):
    hits = {}
    for q in queries or QUERIES:
        for vid, qq in search(q):
            hits.setdefault(vid, qq)
        print(q, len(hits), flush=True)
    with ThreadPoolExecutor(3) as ex:
        metas = list(ex.map(meta, hits))
    with open(out, "w", newline="") as f:
        w = csv.writer(f, delimiter="\t")
        w.writerow(["id", "channel", "channel_id", "license", "duration", "height", "title", "query"])
        for m in metas:
            if not m:
                continue
            lic = m.get("license") or ""
            title = m.get("title", "")
            if "Creative Commons" not in lic or not any(k in title.lower() for k in KEEP):
                continue
            w.writerow([m["id"], m.get("channel"), m.get("channel_id"), lic, m.get("duration"), m.get("height"),
                        title.replace("\t", " "), hits[m["id"]]])


if __name__ == "__main__":
    main(*sys.argv[1:])

"""Zoomed frame strip from one Exercise3D camera (images only; 2D keypoints place the crop, nothing is drawn).

Usage: python strip.py <set> <cam> <part> <out.jpg> <frame> [frame ...]
  part: full | upper (head..hips) | mid (shoulders..knees) | legs (hips..feet) | feet | arms (shoulders..wrists)
Example: python strip.py squat_0000 cam2 mid ~/bpt-data/ex3d_label_sheets/extra_strict/s0000_r3.jpg 60 66 72 78 84
"""
import gzip, json, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw

S = "/private/tmp/claude-501/-Users-6-month-github-06-month-hanbat-repositories-BPT/d083b446-4e06-45ed-8204-8c6e9f22bd1c/scratchpad/ex3dlab"
ROOT = "/Users/6_month/github/06-month/hanbat/repositories/BPT/outputs/exercise3d_synced"
PART = {"full": range(26), "upper": [0, 1, 2, 3, 4, 5, 6, 11, 12, 17, 18, 19], "mid": [5, 6, 11, 12, 13, 14, 18, 19],
        "legs": [11, 12, 13, 14, 15, 16, 19, 20, 21, 22, 23, 24, 25], "feet": [15, 16, 20, 21, 22, 23, 24, 25],
        "arms": [5, 6, 7, 8, 9, 10, 18]}
set_id, cam, part, out = sys.argv[1:5]
frames = [int(x) for x in sys.argv[5:]]
ex = set_id.split("_")[0]
rows = json.load(gzip.open(f"{S}/blind/{set_id}_{cam}_kp.json.gz", "rt"))
kp = {r[0]: np.array(r[2:], float).reshape(26, 3) for r in rows}
pts = np.concatenate([kp[f][list(PART[part])] for f in frames if f in kp])
pts = pts[pts[:, 2] >= 0.3]
path = f"{ROOT}/{ex}/{set_id}/{cam}.mp4"
W, H = map(int, subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                                         "stream=width,height", "-of", "csv=p=0", path]).decode().split(","))
x0, y0, x1, y1 = pts[:, 0].min(), pts[:, 1].min(), pts[:, 0].max(), pts[:, 1].max()
m = 0.18 * max(x1 - x0, y1 - y0, 60)
box = (int(max(0, x0 - m)), int(max(0, y0 - m)), int(min(W, x1 + m)), int(min(H, y1 + m)))
fs = sorted(set(frames))
expr = "+".join(f"eq(n\\,{f})" for f in fs)
raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-vf", f"select='{expr}'", "-fps_mode", "passthrough",
                      "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"], capture_output=True, check=True).stdout
imgs = {f: Image.frombuffer("RGB", (W, H), raw[i * W * H * 3:(i + 1) * W * H * 3]) for i, f in enumerate(fs)}
th = 360
tiles = []
for f in frames:
    t = imgs[f].crop(box)
    t = t.resize((max(1, int(t.width * th / t.height)), th))
    c = Image.new("RGB", (t.width, th + 14), (20, 20, 20))
    c.paste(t, (0, 14))
    ImageDraw.Draw(c).text((3, 1), f"{cam} f{f}", fill=(255, 255, 0))
    tiles.append(c)
sheet = Image.new("RGB", (sum(t.width for t in tiles), th + 14))
x = 0
for t in tiles:
    sheet.paste(t, (x, 0))
    x += t.width
if sheet.width > 2000:
    sheet = sheet.resize((2000, int(sheet.height * 2000 / sheet.width)))
sheet.save(out, quality=85)
print(out, sheet.size)

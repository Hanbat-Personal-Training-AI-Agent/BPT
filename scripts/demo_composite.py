"""Demo composite video: the app screen recording next to front / side / top views of the on-device 3D skeleton.

Inputs come from the trial demo run (Documents/demo on the phone, collected to ~/bpt-data/demo, never git):
  screen_<ts>.mp4   ReplayKit recording (BPT_SCREEN_RECORD=1)
  pose_<ts>.jsonl   DemoPoseLog (BPT_POSE3D_LOG=1)

Clock: every pose line has t_host = CACurrentMediaTime() seconds. The "screen_record_start" line is written in the
ReplayKit start callback, so video time 0 is taken as that line's t_host (ReplayKit's first frame follows within
about one frame). A pose "frame" line is shown at video time t_host - t_start; panels hold the newest frame not
later than the video time, and blank after 0.5 s without frames (calibration and menus show the 2D-only note).

pose3d: 17 H36M joints x (x, y, z) in normalized crop units (1 = half the person-crop side), y down, z away from
the camera. Each view is centred on the pelvis (joint 0) and drawn at a fixed scale.

Usage: python -I scripts/demo_composite.py screen.mp4 pose.jsonl out.mp4 [--fps 15]
Needs ffmpeg/ffprobe on PATH, numpy and Pillow.
"""
import argparse
import bisect
import json
import subprocess

import numpy as np
from PIL import Image, ImageDraw, ImageFont

BONES = [(0, 1), (1, 2), (2, 3), (0, 4), (4, 5), (5, 6), (0, 7), (7, 8), (8, 9), (9, 10),
         (8, 11), (11, 12), (12, 13), (8, 14), (14, 15), (15, 16)]
LEFT = {(0, 4), (4, 5), (5, 6), (8, 11), (11, 12), (12, 13)}
RIGHT = {(0, 1), (1, 2), (2, 3), (8, 14), (14, 15), (15, 16)}
# view name -> (horizontal axis, sign, vertical axis, sign); y is down in the data, so +y draws downward
VIEWS = [("front (x-y)", 0, 1, 1, 1), ("side (z-y)", 2, 1, 1, 1), ("top (x-z)", 0, 1, 2, -1)]


def probe(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "stream=width,height:format=duration", "-of", "json", path],
                         capture_output=True, text=True, check=True).stdout
    info = json.loads(out)
    s = info["streams"][0]
    return s["width"], s["height"], float(info["format"]["duration"])


def load(path):
    frames, reps, t0 = [], [], None
    for line in open(path):
        try:
            d = json.loads(line)
        except json.JSONDecodeError:
            continue
        if d["type"] == "screen_record_start" and d.get("error") is None and t0 is None:
            t0 = d["t_host"]
        elif d["type"] == "frame":
            frames.append(d)
        elif d["type"] == "rep":
            reps.append(d)
    if t0 is None:
        raise SystemExit("no successful screen_record_start line in the pose log")
    return t0, frames, reps


def font(size):
    for name in ("/System/Library/Fonts/AppleSDGothicNeo.ttc", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            pass
    return ImageFont.load_default()


def draw_view(img, box, joints, view, f):
    name, h, hs, v, vs = view
    x0, y0, x1, y1 = box
    d = ImageDraw.Draw(img)
    d.rectangle(box, outline=(70, 70, 70))
    d.text((x0 + 8, y0 + 6), name, fill=(200, 200, 200), font=f)
    if joints is None:
        return
    cx, cy, scale = (x0 + x1) / 2, (y0 + y1) / 2, (y1 - y0) * 0.3
    p = joints - joints[0]
    pts = [(cx + hs * q[h] * scale, cy + vs * q[v] * scale) for q in p]
    for a, b in BONES:
        color = (80, 160, 255) if (a, b) in LEFT else (255, 120, 80) if (a, b) in RIGHT else (230, 230, 230)
        d.line([pts[a], pts[b]], fill=color, width=4)
    for x, y in pts:
        d.ellipse([x - 4, y - 4, x + 4, y + 4], fill=(255, 255, 255))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("screen")
    ap.add_argument("pose")
    ap.add_argument("out")
    ap.add_argument("--fps", type=float, default=15)
    a = ap.parse_args()

    w, h, duration = probe(a.screen)
    t0, frames, reps = load(a.pose)
    times = [fr["t_host"] - t0 for fr in frames]
    rep_times = [r["t_host"] - t0 for r in reps]
    pw = h // 3 * 1  # panel column width = one view height
    vh = h // 3
    small, big = font(max(14, vh // 18)), font(max(16, vh // 14))

    enc = subprocess.Popen(["ffmpeg", "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{pw}x{h}",
                            "-r", str(a.fps), "-i", "-", "-i", a.screen, "-filter_complex",
                            f"[1:v]fps={a.fps}[s];[s][0:v]hstack=inputs=2,format=yuv420p[v]", "-map", "[v]",
                            "-an", "-c:v", "libx264", "-crf", "20", "-shortest", a.out], stdin=subprocess.PIPE)
    n = int(duration * a.fps)
    for k in range(n):
        t = k / a.fps
        img = Image.new("RGB", (pw, h), (18, 18, 18))
        i = bisect.bisect_right(times, t) - 1
        fr = frames[i] if i >= 0 and t - times[i] < 0.5 else None
        joints = None
        if fr is not None and fr.get("pose3d"):
            joints = np.array(fr["pose3d"], dtype=float).reshape(17, 3)
        for j, view in enumerate(VIEWS):
            draw_view(img, (0, j * vh, pw - 1, (j + 1) * vh - 1), joints, view, small)
        d = ImageDraw.Draw(img)
        if fr is None:
            d.text((10, vh - 40), "3D: workout only (calibration logs 2D)", fill=(150, 150, 150), font=small)
        else:
            d.text((10, vh - 2 * big.size - 12), f"{fr['exercise']}  rep {fr['rep']}", fill=(255, 255, 255), font=big)
            d.text((10, vh - big.size - 8), f"state {fr['state']}", fill=(200, 200, 200), font=small)
            r = bisect.bisect_right(rep_times, t) - 1
            if r >= 0 and t - rep_times[r] < 4:
                keys = reps[r].get("warnings_3d") or reps[r].get("warnings") or ["ok"]
                d.text((10, 2 * vh - big.size - 8), f"rep {reps[r]['rep']}: {', '.join(keys)}", fill=(255, 220, 90),
                       font=big)
        enc.stdin.write(img.tobytes())
    enc.stdin.close()
    raise SystemExit(enc.wait())


if __name__ == "__main__":
    main()

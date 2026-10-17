"""MM-Fit push-up label audit, numeric only (no images).
For every push-up set in wXX_labels.csv:
  - pose_2d (authors' 2D pose, OpenPose COCO-18 order, verified: neck = shoulder midpoint) shoulder-height signal
    h = mean(wrist_y) - mean(shoulder_y) (px; push-up bottom = trough). Schmitt dips (0.35/0.65 of the window p5..p95,
    9-frame smoothing, same counter as outputs/rep_validation/gt_and_view.py) inside [s, e], in the 3 s before s and the
    1.5 s after e (the evaluator's clip padding, eval_pushup_mmfit.PRE/POST).
  - earbud (eb_l) and phone (sp_r) accelerometer: dominant period in [s, e] by autocorrelation of the detrended
    magnitude (0.8-4 s band) -> count = duration / period.
  - frame clock: frame number vs. sensor unix-ms timestamps (local slope) inside the set.
usage: python -I mmfit_label_audit.py <mm-fit root> <out.json>
"""
import csv, glob, json, os, sys
import numpy as np
root, out = sys.argv[1], sys.argv[2]
PRE, POST = 90, 45
def smooth(x, k=9): return np.convolve(np.pad(x, k // 2, mode='edge'), np.ones(k) / k, mode='valid')
def dips(n, lo=0.35, hi=0.65):
    reps, armed, st = [], n[0] > hi, None
    for i, v in enumerate(n):
        if v > hi:
            if not armed and st is not None: reps.append(st + int(np.argmin(n[st:i])))
            armed, st = True, None
        elif v < lo and armed: armed, st = False, i
    return reps
def acc_count(a, s, e):
    m = (a[:, 0] >= s) & (a[:, 0] <= e)
    if m.sum() < 50: return None
    t = a[m, 1] / 1000; x = np.linalg.norm(a[m, 2:5], axis=1)
    fs = 50.0; tt = np.arange(t[0], t[-1], 1 / fs); x = np.interp(tt, t, x)
    k = int(fs * 2); x = x - np.convolve(np.pad(x, k // 2, mode='edge'), np.ones(k) / k, mode='valid')[:len(x)]
    ac = np.correlate(x, x, 'full')[len(x) - 1:]; ac /= ac[0] + 1e-9
    lo, hi = int(0.8 * fs), int(4 * fs)
    lag = lo + int(np.argmax(ac[lo:hi])); return dict(period_s=round(lag / fs, 3), count=round((tt[-1] - tt[0]) / (lag / fs), 2), ac=round(float(ac[lag]), 3))
res = []
for lab in sorted(glob.glob(f'{root}/w*/w*_labels.csv')):
    w = os.path.basename(lab)[:3]
    rows = [r for r in csv.reader(open(lab)) if r and r[3] == 'pushups']
    p = np.load(f'{root}/{w}/{w}_pose_2d.npy'); fr = p[0, :, 0].astype(int)
    X, Y = p[0, :, 1:], p[1, :, 1:]
    acc = {k: np.load(f'{root}/{w}/{w}_{k}.npy') for k in ('eb_l_acc', 'sp_r_acc', 'sw_l_acc')}
    for k, (s, e, n, _) in enumerate(rows, 1):
        s, e, n = int(s), int(e), int(n)
        a, b = s - PRE, e + POST
        idx = np.searchsorted(fr, np.arange(a, b + 1)); idx = idx.clip(0, len(fr) - 1)
        present = fr[idx] == np.arange(a, b + 1)
        sh = np.nanmean(np.where(Y[idx][:, [2, 5]] > 0, Y[idx][:, [2, 5]], np.nan), 1)
        wr = np.nanmean(np.where(Y[idx][:, [4, 7]] > 0, Y[idx][:, [4, 7]], np.nan), 1)
        h = wr - sh; ok = present & np.isfinite(h)
        hh = np.interp(np.arange(len(h)), np.where(ok)[0], h[ok]) if ok.sum() > 10 else np.zeros(len(h))
        hh = smooth(hh); win = hh[PRE:PRE + e - s + 1]
        p5, p95 = np.percentile(win, [5, 95]); nn = (hh - p5) / (p95 - p5 + 1e-9)
        all_d = dips(nn); frames_d = [a + d for d in all_d]
        inside = [f for f in frames_d if s <= f <= e]; before = [f for f in frames_d if f < s]; after = [f for f in frames_d if f > e]
        ts = acc['eb_l_acc']; m = (ts[:, 0] >= s) & (ts[:, 0] <= e)
        slope = float(np.polyfit(ts[m, 1] / 1000, ts[m, 0], 1)[0]) if m.sum() > 10 else None
        r = dict(set=f'{w}_s{k}', w=w, start=s, end=e, truth=n, frames=e - s + 1,
                 pose_missing_frames=int((~present).sum()), pose_bad_frames=int((~ok).sum()),
                 pose2d_dips_inside=len(inside), pose2d_dips_before=before, pose2d_dips_after=after,
                 pose2d_dip_frames=inside, first_dip_after_start=(inside[0] - s) if inside else None,
                 last_dip_before_end=(e - inside[-1]) if inside else None,
                 frame_clock_fps=round(slope, 3) if slope else None,
                 acc={k2: acc_count(v, s, e) for k2, v in acc.items()})
        res.append(r)
        print(r['set'], n, 'pose2d', len(inside), 'pre', len(before), 'post', len(after), 'acc',
              {k2: (v or {}).get('count') for k2, v in r['acc'].items()}, 'fps', r['frame_clock_fps'], 'miss', r['pose_missing_frames'], flush=True)
json.dump(res, open(out, 'w'), indent=1)

"""Fit3D rep_ann audit (numeric only): mocap periodicity vs rep_ann boundaries, video frame count vs mocap length.
usage: python -I fit3d_repann_audit.py <fit3d_train_root> <out.json>"""
import glob, json, os, subprocess, sys
import numpy as np
root, out = sys.argv[1], sys.argv[2]
def smooth(x, k=9): return np.convolve(np.pad(x, k // 2, mode='edge'), np.ones(k) / k, mode='valid')
def troughs(sig, lo=0.35, hi=0.65):
    p5, p95 = np.percentile(sig, [5, 95]); n = (sig - p5) / (p95 - p5 + 1e-9)
    reps, armed, start = [], n[0] > hi, None
    for i, v in enumerate(n):
        if v > hi:
            if not armed and start is not None: reps.append(int(start + np.argmin(n[start:i])))
            armed, start = True, None
        elif v < lo and armed: armed, start = False, i
    return reps, n
res = {}
for sd in sorted(glob.glob(f'{root}/s*')):
    subj = os.path.basename(sd); ann = json.load(open(f'{sd}/rep_ann.json'))
    for ex in ('squat', 'pushup', 'barbell_row'):
        jf = f'{sd}/joints3d_25/{ex}.json'
        if not os.path.exists(jf) or ex not in ann: continue
        P = np.array(json.load(open(jf))['joints3d_25'], float)
        cps = sorted(glob.glob(f'{sd}/camera_parameters/*/{ex}.json'))
        R = [np.array(json.load(open(c))['extrinsics']['R'], float) for c in cps]
        up = -np.mean([r[1] for r in R], axis=0); up /= np.linalg.norm(up)
        sh = (P[:, 11] + P[:, 14]) / 2
        sig = {'squat': P[:, 0] @ up, 'pushup': sh @ up,
               'barbell_row': np.linalg.norm((P[:, 13] + P[:, 16]) / 2 - sh, axis=1)}[ex]
        sig = smooth(sig); b = ann[ex]
        inside, _ = troughs(sig[b[0]:b[-1] + 1]); inside = [b[0] + t for t in inside]
        whole, n = troughs(sig)
        per_seg = [sum(b[i] <= t < b[i + 1] for t in inside) for i in range(len(b) - 1)]
        outside = [t for t in whole if t < b[0] or t > b[-1]]
        # outside dips that reach the in-window depth (normalised by window p5..p95)
        w = sig[b[0]:b[-1] + 1]; p5, p95 = np.percentile(w, [5, 95])
        nw = (sig - p5) / (p95 - p5 + 1e-9)
        def dips(seg, off):  # Schmitt dips with the in-window scale (a rep-like dip outside the annotation)
            out, armed, st = [], True, None
            for i, v in enumerate(seg):
                if v > 0.65:
                    if not armed and st is not None: out.append(off + st + int(np.argmin(seg[st:i])))
                    armed, st = True, None
                elif v < 0.35 and armed: armed, st = False, i
            return out
        deep_out = dips(nw[:b[0]], 0) + dips(nw[b[-1] + 1:], b[-1] + 1)
        vids = sorted(glob.glob(f'{sd}/videos/*/{ex}.mp4'))
        nf = []
        for v in vids:
            r = subprocess.run(['ffprobe', '-v', 'error', '-select_streams', 'v', '-show_entries', 'stream=nb_frames,r_frame_rate', '-of', 'csv=p=0', v], capture_output=True, text=True).stdout.strip()
            nf.append(r)
        res[f'{subj}_{ex}'] = dict(subject=subj, exercise=ex, mocap_frames=len(P), ann=b, truth=len(b) - 1,
                                   troughs_in_window=len(inside), per_segment=per_seg, outside_troughs=outside,
                                   outside_deep=deep_out, videos=nf)
        print(subj, ex, len(P), 'truth', len(b) - 1, 'in', len(inside), per_seg, 'out', outside, 'deep_out', deep_out, nf[:1], flush=True)
json.dump(res, open(out, 'w'), indent=1)

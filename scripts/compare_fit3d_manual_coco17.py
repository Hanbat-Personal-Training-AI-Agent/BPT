"""Compare Fit3D COCO17 label sources with the user's manual COCO-definition clicks (track fit3d-label-verify).

Inputs (both local only, never in git: Fit3D-derived):
  --candidates  candidates.json from `verify_fit3d_coco17.py sample` (every source in crop pixels, crop scale, person box)
  --manual      one or more exports of tools/fit3d_annot/index.html (fit3d_coco_manual*.json; later files win per frame)
Per joint (all 17) and source (gvhmr, native, h36m, mocap, rtmpose_m = reference only, not truth):
  n, median error in original-image px, median / mean error / person-box long side, PCK@0.05 / @0.1,
  bias = mean (source - manual) / box along the body axes from the manual clicks (up = hip centre -> shoulder centre,
  side = person's left hip -> right hip, orthogonalised), swaps = flipped source is < half the error and error > 0.1.
Only clicks not marked unsure count by default (--include-unsure adds them). Repeat frames (id ending in r) give the
click repeatability per joint (same image clicked twice) and are not used as references.
Prints aggregate tables (no coordinates) and writes --out JSON. `--selftest` checks the maths on synthetic data.
"""

import argparse
import json

import numpy as np

NAMES = ('nose', 'l_eye', 'r_eye', 'l_ear', 'r_ear', 'l_sh', 'r_sh', 'l_el', 'r_el', 'l_wr', 'r_wr',
         'l_hip', 'r_hip', 'l_kn', 'r_kn', 'l_an', 'r_an')
FLIP = [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15]
SOURCES = ('gvhmr', 'native', 'h36m', 'mocap', 'rtmpose_m')


def arr(points):
    return np.array([[np.nan, np.nan] if p is None or p[0] is None else p for p in points], float)


def merge_manual(paths):
    frames = {}
    for p in paths:
        frames.update(json.load(open(p))['frames'])
    return frames


def body_axes(m, fallback):
    """Manual points [17,2] (nan allowed) -> unit up, side vectors; missing torso joints taken from the fallback source."""
    q = np.where(np.isfinite(m), m, fallback)
    up = q[5:7].mean(0) - q[11:13].mean(0)
    up /= np.linalg.norm(up) + 1e-9
    side = q[12] - q[11]
    side = side - side @ up * up
    side /= np.linalg.norm(side) + 1e-9
    return up, side


def compare(cand, frames, include_unsure=False):
    acc = {s: {j: {'e': [], 'px': [], 'up': [], 'side': [], 'swap': 0} for j in range(17)} for s in SOURCES}
    clicks = {j: {'clicked': 0, 'unsure': 0, 'skipped': 0} for j in range(17)}
    rep = {j: [] for j in range(17)}
    used = 0
    for fid, r in frames.items():
        base = r.get('repeat_of') or (fid[:-1] if fid.endswith('r') else None)
        m = arr(r['points'])
        uns = np.array(r['unsure'], bool)
        if base:   # repeatability
            o = frames.get(base)
            if o and base in cand:
                mo = arr(o['points'])
                d = np.linalg.norm(m - mo, axis=1) / cand[base]['scale'] / cand[base]['box_long_px']
                for j in range(17):
                    if np.isfinite(d[j]) and not (uns[j] or o['unsure'][j]):
                        rep[j].append(float(d[j]))
            continue
        if fid not in cand:
            continue
        c = cand[fid]
        used += 1
        for j in range(17):
            clicks[j]['clicked'] += bool(np.isfinite(m[j]).all())
            clicks[j]['unsure'] += bool(uns[j])
            clicks[j]['skipped'] += bool(r['skipped'][j])
        ok = np.isfinite(m).all(1) & (include_unsure | ~uns)
        up, side = body_axes(m, arr(c['sources']['gvhmr']))
        k = 1.0 / c['scale']                       # crop px -> original px
        box = c['box_long_px']
        for s in SOURCES:
            P = arr(c['sources'][s])
            for j in np.where(ok)[0]:
                if not np.isfinite(P[j]).all():
                    continue
                d = P[j] - m[j]
                e = np.linalg.norm(d) * k / box
                a = acc[s][j]
                a['e'].append(e); a['px'].append(np.linalg.norm(d) * k)
                a['up'].append(d @ up * k / box); a['side'].append(d @ side * k / box)
                if np.isfinite(P[FLIP[j]]).all() and FLIP[j] != j:
                    ef = np.linalg.norm(P[FLIP[j]] - m[j]) * k / box
                    a['swap'] += int(ef < 0.5 * e and e > 0.10)
    out = {'frames_used': used, 'include_unsure': include_unsure, 'sources': {}, 'clicks': {NAMES[j]: v for j, v in clicks.items()}}
    for s in SOURCES:
        out['sources'][s] = {}
        for j in range(17):
            a = acc[s][j]
            if not a['e']:
                out['sources'][s][NAMES[j]] = {'n': 0}
                continue
            e = np.array(a['e'])
            out['sources'][s][NAMES[j]] = {
                'n': len(e), 'px_med': round(float(np.median(a['px'])), 2), 'norm_med': round(float(np.median(e)), 4),
                'norm_mean': round(float(e.mean()), 4), 'pck05': round(float((e < 0.05).mean()), 3), 'pck10': round(float((e < 0.10).mean()), 3),
                'bias_up': round(float(np.mean(a['up'])), 4), 'bias_side': round(float(np.mean(a['side'])), 4), 'swaps': a['swap']}
    out['repeatability'] = {NAMES[j]: ({'n': len(v), 'norm_med': round(float(np.median(v)), 4), 'norm_max': round(float(np.max(v)), 4)} if v else {'n': 0}) for j, v in rep.items()}
    return out


def table(out):
    lines = []
    for metric in ('norm_med', 'pck05', 'pck10', 'bias_up', 'bias_side'):
        lines.append(f'\n### {metric}\n')
        lines.append('| joint | ' + ' | '.join(SOURCES) + ' | n | repeat med |')
        lines.append('|' + '---|' * (len(SOURCES) + 3))
        for j in NAMES:
            row = [str(out['sources'][s][j].get(metric, '–')) for s in SOURCES]
            n = out['sources']['gvhmr'][j]['n']
            rp = out['repeatability'][j].get('norm_med', '–')
            lines.append(f'| {j} | ' + ' | '.join(row) + f' | {n} | {rp} |')
    sw = {s: sum(out['sources'][s][j].get('swaps', 0) for j in NAMES) for s in SOURCES}
    lines.append(f'\nswaps per source: {sw}; frames used: {out["frames_used"]}')
    return '\n'.join(lines)


def selftest():
    rng = np.random.default_rng(0)
    cand, frames = {}, {}
    for f in range(30):
        m = rng.uniform(100, 700, (17, 2))
        m[5], m[6], m[11], m[12] = [350, 300], [450, 300], [370, 500], [430, 500]   # upright, person's left on image left
        src = {}
        for s in SOURCES:
            P = m.copy()
            if s == 'gvhmr':
                P[11:13, 1] += 0.08 * 500 * 0.5        # hips 0.08 box lower (box 500 px original, scale 0.5 crop->orig x2)
            if s == 'native':
                P[[9, 10]] = m[[10, 9]]                 # swapped wrists
            src[s] = P.tolist()
        cand[f'f{f:02d}'] = {'scale': 0.5, 'box_long_px': 500.0, 'sources': src}
        frames[f'f{f:02d}'] = {'points': m.tolist(), 'unsure': [False] * 17, 'skipped': [False] * 17}
    frames['f00r'] = {'points': (np.array(frames['f00']['points']) + [5, 0]).tolist(), 'unsure': [False] * 17, 'skipped': [False] * 17, 'repeat_of': 'f00'}
    frames['f01']['unsure'][0] = True
    o = compare(cand, frames)
    g = o['sources']['gvhmr']
    # gvhmr hips: 20 crop px lower = 40 original px = 0.08 box, i.e. bias down = -0.08 along up
    assert abs(g['l_hip']['norm_med'] - 0.08) < 1e-6 and abs(g['l_hip']['bias_up'] + 0.08) < 1e-6, g['l_hip']
    assert g['l_hip']['pck05'] == 0 and g['l_hip']['pck10'] == 1 and g['l_kn']['norm_med'] == 0
    assert abs(g['l_hip']['px_med'] - 40) < 1e-6
    assert o['sources']['native']['l_wr']['swaps'] == 30 and o['sources']['native']['l_wr']['pck10'] < 0.2
    assert o['sources']['gvhmr']['nose']['n'] == 29 and o['clicks']['nose']['unsure'] == 1
    assert o['repeatability']['l_sh']['n'] == 1 and abs(o['repeatability']['l_sh']['norm_med'] - 5 / 0.5 / 500) < 1e-9
    assert o['frames_used'] == 30
    print('selftest ok')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--candidates')
    ap.add_argument('--manual', nargs='+')
    ap.add_argument('--out')
    ap.add_argument('--include-unsure', action='store_true')
    ap.add_argument('--selftest', action='store_true')
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    out = compare(json.load(open(a.candidates)), merge_manual(a.manual), a.include_unsure)
    if a.out:
        json.dump(out, open(a.out, 'w'), indent=1)
    print(table(out))


if __name__ == '__main__':
    main()

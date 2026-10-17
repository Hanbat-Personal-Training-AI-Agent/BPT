"""Smallest manual check left after approaches A and B (track fit3d-label-verify): "which marker is on the COCO point?".

build  local (Mac). Inputs (Fit3D-derived, local only, never in git):
         ~/Documents/bpt-fit3d-annot/private/candidates.json      label sources in crop px (from verify_fit3d_coco17.py sample)
         ~/Documents/bpt-fit3d-annot/private/consensus40_export.npz  4-model COCO consensus inputs for the same 40 frames
                                                                     (original px, from fit3d_coco17_consensus.py run on Home)
       For the disputed joints only (nose, shoulders, hips) and only where the candidates are visibly apart, writes
         ~/Documents/bpt-fit3d-annot/choice.js            questions: frame, joint, marker positions under shuffled letters
         ~/Documents/bpt-fit3d-annot/private/choice_key.json  letter -> source (kept out of the page so the check is blind)
score  reads the exported answers (fit3d_coco_choice.json) + key -> per joint counts of the chosen source.
"""

import argparse
import json
import os

import numpy as np

H = os.path.expanduser
NAMES = ('nose', 'l_eye', 'r_eye', 'l_ear', 'r_ear', 'l_sh', 'r_sh', 'l_el', 'r_el', 'l_wr', 'r_wr', 'l_hip', 'r_hip', 'l_kn', 'r_kn', 'l_an', 'r_an')
DISPUTED = {0: ('gvhmr', 'consensus'), 5: ('gvhmr', 'consensus', 'h36m'), 6: ('gvhmr', 'consensus', 'h36m'),
            11: ('gvhmr', 'consensus', 'h36m'), 12: ('gvhmr', 'consensus', 'h36m')}
LETTERS = 'ABC'


def consensus(kp, sc, conf=0.3, need=3):
    """kp [M,N,17,2], sc [M,N,17] -> [N,17,2] coordinate median of confident models (nan if < need). Same rule as approach B."""
    ok = sc > conf
    x = np.where(ok[..., None], kp, np.nan)
    c = np.nanmedian(x, axis=0)
    c[ok.sum(0) < need] = np.nan
    return c


def build(a):
    cand = json.load(open(a.candidates))
    E = np.load(a.consensus, allow_pickle=True)
    srcs = list(E['sources'])
    C = consensus(E['kp'], E['sc'])
    rng = np.random.default_rng(20261018)
    rows = []
    for n, fid in enumerate(E['tag']):
        c = cand[str(fid)]
        g_crop = np.array(c['sources']['gvhmr'], float)
        g_orig = E['labels'][n, srcs.index('gvhmr')]
        s = c['scale']
        t = (g_crop - s * g_orig).mean(0)              # crop = s * orig + t (pure scale + shift crop)
        fit_err = float(np.abs(g_crop - (s * g_orig + t)).max())
        assert fit_err < 0.5, (fid, fit_err)
        pts = {'consensus': s * C[n] + t}
        for k in ('gvhmr', 'h36m'):
            pts[k] = np.array([[np.nan, np.nan] if v[0] is None else v for v in c['sources'][k]], float)
        box = c['box_long_px'] * s
        prone = bool(E['prone'][n])
        for j, opts in DISPUTED.items():
            P = {k: pts[k][j] for k in opts if np.isfinite(pts[k][j]).all()}
            if 'consensus' not in P or 'gvhmr' not in P:
                continue
            sep = np.linalg.norm(P['gvhmr'] - P['consensus']) / box
            # drop a third marker that sits on top of another one (< 1.5% of the box): it cannot be told apart
            for k in list(P):
                if k not in ('gvhmr', 'consensus') and min(np.linalg.norm(P[k] - P[o]) / box for o in ('gvhmr', 'consensus')) < 0.015:
                    del P[k]
            rows.append({'fid': str(fid), 'joint': j, 'sep': float(sep), 'prone': prone, 'exercise': str(E['exercise'][n]), 'P': P, 'box': box})
    # choose frames: prone frames with the largest gvhmr-consensus separations first, then non-prone, <= a.frames frames
    by_f = {}
    for r in rows:
        if r['sep'] >= a.min_sep:
            by_f.setdefault(r['fid'], []).append(r)
    score = {f: (any(r['prone'] for r in v), sum(r['sep'] for r in v)) for f, v in by_f.items()}
    prone_f = sorted([f for f in by_f if score[f][0]], key=lambda f: -score[f][1])
    other_f = sorted([f for f in by_f if not score[f][0]], key=lambda f: -score[f][1])
    n_prone = min(len(prone_f), a.frames - a.non_prone)
    pick = prone_f[:n_prone] + other_f[:a.frames - n_prone]
    if a.include_f00 and 'f00' not in pick and 'f00' in by_f:
        pick = pick[:a.frames - 1] + ['f00']   # f00 already has the user's own clicks -> known-answer consistency check
    qs, key = [], {}
    for f in pick:
        for r in sorted(by_f[f], key=lambda r: r['joint']):
            names = list(r['P'])
            rng.shuffle(names)
            qid = f'{f}_{NAMES[r["joint"]]}'
            key[qid] = {LETTERS[i]: k for i, k in enumerate(names)}
            key[qid]['_sep_gvhmr_consensus_box'] = round(r['sep'], 4)
            key[qid]['_prone'] = r['prone']
            key[qid]['_exercise'] = r['exercise']
            qs.append({'id': qid, 'img': f'frames/{f}.jpg', 'joint': NAMES[r['joint']], 'zoom': round(0.22 * r['box'], 1),
                       'markers': [{'letter': LETTERS[i], 'xy': [round(float(r['P'][k][0]), 1), round(float(r['P'][k][1]), 1)]} for i, k in enumerate(names)]})
    open(a.out_js, 'w').write('window.CHOICES = ' + json.dumps(qs, ensure_ascii=False) + ';\n')
    json.dump(key, open(a.out_key, 'w'), indent=1)
    print(f'{len(pick)} frames {pick}, {len(qs)} questions; prone frames {sum(score[f][0] for f in pick)}')


def score(a):
    key = json.load(open(a.out_key))
    ans = json.load(open(a.answers))['answers']
    out = {}
    for qid, v in ans.items():
        j = qid.split('_', 1)[1]
        k = key[qid]
        choice = k.get(v.get('choice'), v.get('choice'))   # letter -> source, or 'none' / 'unsure'
        grp = 'prone' if k['_prone'] else 'upright'
        out.setdefault(j, {}).setdefault(grp, {}).setdefault(choice, 0)
        out[j][grp][choice] += 1
    print(json.dumps(out, indent=1, ensure_ascii=False))


def selftest():
    kp = np.zeros((4, 1, 17, 2))
    kp[:, 0, 0, 0] = [1, 2, 3, 100]
    sc = np.ones((4, 1, 17))
    sc[3] = 0.1
    c = consensus(kp, sc)
    assert c[0, 0, 0] == 2 and np.isfinite(c).all()
    sc[2] = 0.1
    assert np.isnan(consensus(kp, sc)[0, 0, 0])
    print('selftest ok')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=('build', 'score', 'selftest'))
    ap.add_argument('--candidates', default=H('~/Documents/bpt-fit3d-annot/private/candidates.json'))
    ap.add_argument('--consensus', default=H('~/Documents/bpt-fit3d-annot/private/consensus40_export.npz'))
    ap.add_argument('--out-js', default=H('~/Documents/bpt-fit3d-annot/choice.js'))
    ap.add_argument('--out-key', default=H('~/Documents/bpt-fit3d-annot/private/choice_key.json'))
    ap.add_argument('--answers', default=H('~/Documents/bpt-fit3d-annot/fit3d_coco_choice.json'))
    ap.add_argument('--frames', type=int, default=10)
    ap.add_argument('--non-prone', type=int, default=3)
    ap.add_argument('--min-sep', type=float, default=0.03)
    ap.add_argument('--include-f00', action='store_true', default=True)
    a = ap.parse_args()
    {'build': build, 'score': score, 'selftest': lambda a: selftest()}[a.cmd](a)


if __name__ == '__main__':
    main()

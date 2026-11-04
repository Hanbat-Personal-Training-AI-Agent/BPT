"""finetune3 XS pre-registered rule check (docs/results/finetune3_plan.md §1, A / A' / B / C / D) from the held-out outputs:
lift-app T4 json (Fit3D s07-s11 real cameras, app path), xs_eval json (experiment-A Halpe26 input, virtual grid), Core ML
parity jsons. Prints a markdown table per candidate and the C1 / C2 preference. Valgus-if-3D is a hypothetical rule (the live
squat_knee_valgus stays front-gated in 2D) and is left out of C.

usage: xs_rules.py --t4 t4.json --xs eval.json --base ftr05 --cands C1,C2 [--parity C1=parity_C1.json,C2=...]
"""
import argparse, json

import numpy as np


def xs_cell(rows, kind, src=None, noise=None, bucket=None):
    rs = [r for r in rows if r['kind'] == kind and (src is None or r.get('src') == src)
          and (noise is None or (r['noise'] == 'clean') == (noise == 'clean')) and (bucket is None or r['bucket'] == bucket)]
    med = lambda k: float(np.median([x for r in rs for x in r.get(f'{k}_rep', [])])) if rs else float('nan')
    return dict(n=len(rs), mpjpe=float(np.mean([r['mpjpe'] for r in rs])) if rs else float('nan'), knee=med('knee'), elbow=med('elbow'))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--t4', required=True); p.add_argument('--xs', required=True)
    p.add_argument('--base', default='ftr05'); p.add_argument('--cands', default='C1,C2'); p.add_argument('--parity', default='')
    a = p.parse_args()
    t4, xs = json.load(open(a.t4)), json.load(open(a.xs))['rows']
    par = dict(kv.split('=', 1) for kv in a.parity.split(',') if kv)
    B = a.base
    pose = lambda m, ex='all': t4['pose'][f'heldout/{ex}/{m}']
    rules = lambda m: {k: v for ex in ('squat', 'pushup', 'barbell_row') for k, v in t4['rules'][f'{ex}/heldout/{m}']['current'].items()
                       if k != 'valgus_if_front'}
    res = {}
    for C in a.cands.split(','):
        b, c = pose(B), pose(C)
        chk = []
        add = lambda name, val, lim, ok: chk.append((name, val, lim, ok))
        add('A MPJPE', c['mpjpe']['mean'], f"≤ {b['mpjpe']['mean'] + 1:.1f}", c['mpjpe']['mean'] <= b['mpjpe']['mean'] + 1)
        add('A PA-MPJPE', c['pa']['mean'], f"≤ {b['pa']['mean'] + 1:.1f}", c['pa']['mean'] <= b['pa']['mean'] + 1)
        for k in ('knee', 'hip', 'elbow', 'torso_g'):
            add(f'A {k} rep-extreme p50', c[k]['p50'], f"≤ {b[k]['p50'] + 1:.1f}", c[k]['p50'] <= b[k]['p50'] + 1)
        for ex in ('squat', 'pushup', 'barbell_row'):
            v, w = pose(C, ex)['mpjpe']['mean'], pose(B, ex)['mpjpe']['mean']
            add(f'A {ex} MPJPE', v, f'≤ {w + 3:.1f}', v <= w + 3)
        add('A knee flip', c['flip'], f"≤ {b['flip'] + 0.005:.4f}", c['flip'] <= b['flip'] + 0.005)
        add('A invalid-joint frames', c['partial'], f"≤ {b['partial'] + 0.005:.4f}", c['partial'] <= b['partial'] + 0.005)
        hb, hc = xs_cell(xs[B], 'R', 'Ahalpe'), xs_cell(xs[C], 'R', 'Ahalpe')
        add("A' Halpe26 input MPJPE", hc['mpjpe'], f"≤ {hb['mpjpe'] + 1:.1f}", hc['mpjpe'] <= hb['mpjpe'] + 1)
        add("A' Halpe26 knee rep p50", hc['knee'], f"≤ {hb['knee'] + 1:.1f}", hc['knee'] <= hb['knee'] + 1)
        add("A' Halpe26 elbow rep p50", hc['elbow'], f"≤ {hb['elbow'] + 1:.1f}", hc['elbow'] <= hb['elbow'] + 1)
        vb, vc = xs_cell(xs[B], 'V', noise='noisy', bucket='side<=40'), xs_cell(xs[C], 'V', noise='noisy', bucket='side<=40')
        bi = c['mpjpe']['mean'] <= b['mpjpe']['mean'] - 2
        bii = vc['mpjpe'] <= vb['mpjpe'] - 5 and vc['knee'] <= vb['knee'] and vc['elbow'] <= vb['elbow']
        add('B(i) real MPJPE gain', c['mpjpe']['mean'], f"≤ {b['mpjpe']['mean'] - 2:.1f}", bi)
        add('B(ii) virtual side MPJPE / knee / elbow', f"{vc['mpjpe']:.1f} / {vc['knee']:.1f} / {vc['elbow']:.1f}",
            f"≤ {vb['mpjpe'] - 5:.1f} / {vb['knee']:.1f} / {vb['elbow']:.1f}", bii)
        rb, rc = rules(B), rules(C)
        worst = max(rc, key=lambda k: rc[k] - rb[k])
        add('C per-key false alarms (worst key)', f'{worst} {rc[worst]:.2f}', f'≤ {rb[worst] + 0.05:.2f}', all(rc[k] <= rb[k] + 0.05 for k in rc))
        add('C sum of false-alarm rates', sum(rc.values()), f'≤ {sum(rb.values()):.2f}', sum(rc.values()) <= sum(rb.values()) + 1e-9)
        if C in par:
            q = json.load(open(par[C]))
            add('D Core ML ALL / CPU (rel. joint spread)', f"{q['ALL']['rel_to_joint_spread']:.4f} / {q['CPU_ONLY']['rel_to_joint_spread']:.4f}",
                '≤ 0.005 / 0.010', q['ALL']['rel_to_joint_spread'] <= 0.005 and q['CPU_ONLY']['rel_to_joint_spread'] <= 0.010)
        A = all(ok for n, _, _, ok in chk if n.startswith(('A ', "A'")))
        Bok = bi or bii
        Cok = all(ok for n, _, _, ok in chk if n.startswith('C '))
        Dok = all(ok for n, _, _, ok in chk if n.startswith('D ')) if C in par else None
        res[C] = dict(A=A, B=Bok, C=Cok, D=Dok, passed=bool(A and Bok and Cok and Dok), real=c['mpjpe']['mean'], vside=vc['mpjpe'])
        print(f'\n### {C} vs {B}\n\n| rule | {C} | limit | ok |\n|---|---|---|---|')
        for n, v, lim, ok in chk:
            print(f"| {n} | {v if isinstance(v, str) else f'{v:.4g}'} | {lim} | {'✓' if ok else '✗'} |")
        print(f"\n{C}: A {A}, B {Bok}, C {Cok}, D {Dok} -> {'PASS' if res[C]['passed'] else 'FAIL'}")
    if all(k in res for k in ('C1', 'C2')):
        c1, c2 = res['C1'], res['C2']
        if c1['passed'] and c2['passed']:
            pick = 'C2' if (c1['real'] - c2['real'] >= 2.0 or c1['vside'] - c2['vside'] >= 5.0) else 'C1'
        else:
            pick = 'C1' if c1['passed'] else 'C2' if c2['passed'] else 'none'
        print(f'\npre-registered preference: {pick}')


if __name__ == '__main__':
    main()

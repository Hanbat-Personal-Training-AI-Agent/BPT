"""eval-full: normal-rep false alarms per key on the rules-calib held-out normal sets (public held-out good clips with
AI-consensus normal form, Exercise3D P2/P3), Python app path sets (pubpy). Rules = rules-calib form_rules.judge (the
Swift FormRulePreset mirror): app_default (R-all), app_default with the six noisy keys not delivered (R-6off), and
the model's rc1 preset where one exists (R-rc1). Denominator = every judged rep of the normal sets (not the
per-rule view gate of rules_calib_tables.md); setup_* prompts are left out. Same set preparation as rules_calib_analysis.prepare.

usage (Home): pub_false_alarms.py --rules-code ~/bpt-runs/rules-calib/_code/1682416 --sets a.json.gz,b.json.gz --presets-dir RULES --out OUT
"""
import argparse, gzip, json, sys
from collections import defaultdict

NOISY6 = {'squat_no_lockout', 'squat_knee_valgus', 'pushup_no_lockout', 'pushup_hip_pike', 'pushup_shallow', 'pushup_head_up'}
RC1 = {'orig': 'xs_orig_rc1', 'c1': 'xs_c1_rc1', 'c2': 'xs_c2_rc1'}


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--rules-code', required=True); p.add_argument('--sets', required=True); p.add_argument('--out', required=True)
    p.add_argument('--presets-dir', required=True, help='pose_feedback/rules of the final rules-calib commit (rc1 presets)')
    a = p.parse_args()
    sys.path[:0] = [a.rules_code, f'{a.rules_code}/scripts']
    from pose_feedback.feedback.form_rules import judge, load_preset
    from rules_calib_analysis import is_normal, prepare
    sets = []
    for f in a.sets.split(','):
        sets += json.load(gzip.open(f))
    sets = prepare([s for s in sets if s.get('group') == 'heldout' and s['src'] in ('public', 'ex3d') and is_normal(s)])
    dv, doff = load_preset('app_default')
    cnt = defaultdict(lambda: defaultdict(int))  # (model, src, ex, rules) -> key -> n ; '_reps'
    for s in sets:
        if not s['jreps']: continue
        ms = [r['m'] for r in s['jreps']]; sv = [r['side_view'] for r in s['jreps']]; m, ex = s['model'], s['exercise']
        rules = {'R-all': judge(ms, ex, dv, doff, side_view=sv)}
        if m in RC1:
            v, off = load_preset(f'{a.presets_dir}/{RC1[m]}.json'); rules['R-rc1'] = judge(ms, ex, v, off, side_view=sv)
        for rn, fired in rules.items():
            for f in fired:
                c = cnt[(m, s['src'], ex, rn)]; c['_reps'] += 1; f = {k for k in f if not k.startswith('setup_')}  # setup prompts are not form alarms
                c['_any'] += bool(f)
                for k in f: c[k] += 1
                if rn == 'R-all':
                    c6 = cnt[(m, s['src'], ex, 'R-6off')]; c6['_reps'] += 1; c6['_any'] += bool(f - NOISY6)
                    for k in f - NOISY6: c6[k] += 1
    out = {'|'.join(k): dict(v) for k, v in sorted(cnt.items())}
    json.dump(out, open(f'{a.out}.json', 'w'), indent=1)
    md = ['| 모델 | 출처 | 운동 | 규칙 | 정상 렙 | 아무 키라도 | 키별(≥1%) |', '|---|---|---|---|---|---|---|']
    for k, v in sorted(cnt.items()):
        n = v['_reps']
        keys = ', '.join(f'{q} {c / n:.0%}' for q, c in sorted(v.items(), key=lambda x: -x[1]) if not q.startswith('_') and c / n >= 0.01)
        md.append(f"| {k[0]} | {k[1]} | {k[2]} | {k[3]} | {n} | {v['_any'] / n:.0%} | {keys or '–'} |")
    open(f'{a.out}.md', 'w').write('\n'.join(md) + '\n'); print('\n'.join(md))


if __name__ == '__main__':
    main()

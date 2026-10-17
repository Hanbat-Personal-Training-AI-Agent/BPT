"""Initial-failure / loss frequency per model from track_events.py JSONs. usage: loss_freq.py <ana_dir> <name>..."""
import json, sys, collections
A = sys.argv[1]
for name in sys.argv[2:]:
    R = json.load(open(f'{A}/{name}.json'))
    for m in ('mcoco17', 'halpe26'):
        rr = [r for r in R if r['clip'].endswith(f'_{m}.csv')]
        c = collections.Counter(r['initial_failure'] for r in rr)
        lost = [r for r in rr if r['losses_after_sustained'] > 0]
        late = [r['clip'].rsplit('_', 2)[0] for r in rr if r['initial_failure'] in ('late_acquire', 'never_sustained')]
        delays = [d for r in rr for d in r['reacq_delays']]
        full = sum(r['full_inputs'] for r in rr); frames = sum(r['frames'] for r in rr)
        print(f"{name:20s} {m:8s} n={len(rr):3d} late/never={len(late):2d} loss-after-sustained sets={len(lost):2d} "
              f"(never re-acquired {sum(d is None for d in delays)}, delays {sorted(d for d in delays if d is not None)[:10]}) "
              f"whole-frame inputs {full}/{frames} ({full/frames:.1%}) late:{late[:10]}")


def paired(name):
    R = json.load(open(f'{A}/{name}.json'))
    by = collections.defaultdict(dict)
    for r in R:
        stem, m = r['clip'][:-4].rsplit('_', 1); by[stem][m] = r
    pairs = [v for v in by.values() if len(v) == 2]
    late = lambda r: r['initial_failure'] in ('late_acquire', 'never_sustained')
    loss = lambda r: r['losses_after_sustained'] > 0
    for lab, f in (('late/never', late), ('loss-after-sustained', loss)):
        b = sum(f(v['mcoco17']) and f(v['halpe26']) for v in pairs); c = sum(f(v['mcoco17']) and not f(v['halpe26']) for v in pairs)
        h = sum(f(v['halpe26']) and not f(v['mcoco17']) for v in pairs)
        print(f"  {name} {lab}: both {b}, COCO17 only {c}, Halpe26 only {h} (of {len(pairs)} paired)")


if __name__ == "__main__":
    for n in sys.argv[2:]: paired(n)

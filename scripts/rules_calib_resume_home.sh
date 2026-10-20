#!/bin/bash
# Resume the already registered 2026-10-20 Halpe26 rules experiments on Home.
# Usage: SHA=<immutable code directory> bash scripts/rules_calib_resume_home.sh
# Existing evaluations are waited for, never restarted. All outputs stay on Home.
set -euo pipefail
F=$HOME/bpt-runs/rules-calib
C=$F/_code/${SHA:?Set SHA to the deployed immutable code snapshot}
PY=$HOME/miniconda3/envs/bpt-home/bin/python
cd "$F"
exec 9>"$F/.resume-20261020.lock"
flock -n 9 || { echo "Another rules continuation owns the lock"; exit 1; }
trap 'rc=$?; echo "$(date -Is) FAILED line $LINENO exit $rc"; exit "$rc"' ERR
EVAL=$C/scripts/eval_rules_calib.py
ORIG=$HOME/models/MotionAGFormer/checkpoint/motionagformer-xs-h36m.pth.tr
C1=$HOME/bpt-runs/finetune3/xs-C1/xs.pth
C2=$HOME/bpt-runs/finetune3/xs-C2/xs.pth
SETS=sets_pubpy_halpe26_orig_c1.json.gz

wait_for() {
    local run=$1 file=$2 pid=$3
    until [ -s "$run/$file" ] && [ -s "$run/manifest.json" ]; do
        if [ "$pid" = 0 ] || ! kill -0 "$pid" 2>/dev/null; then
            echo "Missing completed $run/$file; expected producer PID $pid is gone"
            return 1
        fi
        sleep 60
    done
    "$PY" - "$run" "$file" <<'PY'
import hashlib, json, sys
from pathlib import Path
r, filename = Path(sys.argv[1]), sys.argv[2]
m = json.loads((r / 'manifest.json').read_text())
expected = [v for k, v in m['outputs'].items() if Path(k).name == filename]
assert len(expected) == 1, (r, 'missing or ambiguous output hash')
assert hashlib.sha256((r / filename).read_bytes()).hexdigest() == expected[0], (r, 'hash mismatch')
print('Completed and hash verified:', r, flush=True)
PY
}

echo "$(date -Is) Waiting for existing evaluations; code $SHA"
wait_for 20261020-pubpy-h26-held "$SETS" 182977
wait_for 20261020-pubpy-h26-tune-ex3d "$SETS" 184446
wait_for 20261020-fit3d-h26A-c1held sets_fit3d_halpeA.json.gz 193498
wait_for 20261020-pubpy-h26-tune2d-part1 "$SETS" 195963
wait_for 20261020-fit3d-h26A-orig sets_fit3d_halpeA.json.gz 0

# The Mac finished all 62 normal tuning clips; the running part 1 captured the first 54.
# Capture only the remaining 8 JSON references, and combine all references for C2.
"$PY" - <<'PY'
import hashlib, json, time
from pathlib import Path
root = Path.cwd()
full = root / '20261020-pub-tune2d-h26-2ef3ced'
part1 = root / '20261020-pub-tune2d-h26-2ef3ced-part1'
allfiles = {p.name: p for p in full.glob('*_halpe26.json')}
first = {p.name for p in part1.glob('*_halpe26.json')}
assert len(allfiles) == 62 and len(first) == 54 and first <= allfiles.keys(), (len(allfiles), len(first))
inputs = {}
for name in first:
    assert (part1 / name).read_bytes() == allfiles[name].read_bytes(), ('changed part1 reference', name)
subset = root / '20261020-refs-h26-tune2d-part2/pub_tune2d_h26/2d'
subset.mkdir(parents=True, exist_ok=True)
for name in sorted(allfiles.keys() - first):
    dest = subset / name
    if not dest.exists():
        dest.symlink_to(allfiles[name])
    assert dest.resolve() == allfiles[name]
    inputs[str(allfiles[name])] = hashlib.sha256(allfiles[name].read_bytes()).hexdigest()
combined = root / '20261020-refs-h26-all'
sources = {
    'public_held_own_v1': root / '20261020-e2e2d-h26/public_held_own_v1/2d',
    'public_tune_own_v1': root / '20261020-refs-h26/public_tune_own_v1/2d',
    'ex3d_own_v1': root / '20261020-refs-h26/ex3d_own_v1/2d',
    'pub_tune2d_h26': full,
}
counts = {}
for dataset, source in sources.items():
    assert source.is_dir(), source
    dest = combined / dataset / '2d'
    dest.parent.mkdir(parents=True, exist_ok=True)
    if not dest.exists():
        dest.symlink_to(source)
    assert dest.resolve() == source.resolve(), ('reference target changed', dest)
    counts[dataset] = len(list(dest.glob('*_halpe26.json')))
assert counts == dict(public_held_own_v1=192, public_tune_own_v1=65, ex3d_own_v1=39, pub_tune2d_h26=62), counts
json.dump(dict(created=time.strftime('%Y-%m-%d %H:%M:%S %Z'), remaining=sorted(allfiles.keys()-first),
               inputs=inputs, combined_counts=counts),
          open(root / '20261020-refs-h26-tune2d-part2/manifest.json', 'w'), indent=2)
print('Reference inventory:', counts, 'remaining tuning clips', len(inputs), flush=True)
PY

R=20261020-pubpy-h26-tune2d-part2
if [ ! -s "$R/manifest.json" ]; then
    mkdir -p "$R"
    echo "$(date -Is) Starting remaining 8 normal tuning clips"
    nice -n 10 "$PY" -I "$EVAL" pubpy --ref 20261020-refs-h26-tune2d-part2 --pose-model halpe26 \
        --csv-dirs "pub_tune2d_h26=$F/20261020-pub-tune2d-h26-2ef3ced" \
        --models "orig=$ORIG,c1=$C1" --threads 4 --labels "$C/data/eval_sources" \
        --ex3d-gt _inputs/ex3d_gt.json --run-dir "$R" > "$R/log.txt" 2>&1
fi
wait_for "$R" "$SETS" 0
BASESETS="20261020-fit3d-h26A-orig/sets_fit3d_halpeA.json.gz,20261020-fit3d-h26A-c1held/sets_fit3d_halpeA.json.gz,20261020-pubpy-h26-held/$SETS,20261020-pubpy-h26-tune-ex3d/$SETS,20261020-pubpy-h26-tune2d-part1/$SETS,$R/$SETS"
R=20261020-analysis-h26-orig-c1-resumed
if [ ! -s "$R/manifest.json" ]; then
    mkdir -p "$R"
    "$PY" -I "$EVAL" analyze --sets "$BASESETS" --pose2d halpe26 --run-dir "$R" > "$R/log.txt" 2>&1
fi
echo "$(date -Is) ORIG_C1_ANALYSIS_DONE $R"

# A completed training manifest is required, not merely an in-progress checkpoint.
wait_for "$HOME/bpt-runs/finetune3/xs-C2" xs.pth 146000
CSV="public_held_own_v1=$HOME/bpt-runs/eval-reliability/public_held_own_v1,public_tune_own_v1=$HOME/bpt-runs/eval-reliability/public_tune_own_v1,ex3d_own_v1=$HOME/bpt-runs/eval-reliability/ex3d_own_v1,pub_tune2d_h26=$F/20261020-pub-tune2d-h26-2ef3ced"
R=20261020-pubpy-h26-c2
if [ ! -s "$R/manifest.json" ]; then
    mkdir -p "$R"
    nice -n 10 "$PY" -I "$EVAL" pubpy --ref 20261020-refs-h26-all --pose-model halpe26 --csv-dirs "$CSV" \
        --models "c2=$C2" --threads 4 --labels "$C/data/eval_sources" --ex3d-gt _inputs/ex3d_gt.json \
        --run-dir "$R" > "$R/log.txt" 2>&1
fi
wait_for "$R" sets_pubpy_halpe26_c2.json.gz 0
R=20261020-fit3d-h26A-c2
if [ ! -s "$R/manifest.json" ]; then
    mkdir -p "$R"
    nice -n 10 "$PY" -I "$EVAL" fit3d --root "$HOME/datasets/fit3d" --replay "$HOME/bpt-smpl/replay" \
        --subjects s07,s08,s09,s10,s11 --pose2d-dir "$HOME/bpt-runs/lift-compare/A-pose2d-20261019/pose2d" \
        --pose2d-key halpe --models "c2=$C2" --cpu --threads 4 --cache "$F/_cache" --run-dir "$R" > "$R/log.txt" 2>&1
fi
wait_for "$R" sets_fit3d_halpeA.json.gz 0
R=20261020-analysis-h26-all-resumed
if [ ! -s "$R/manifest.json" ]; then
    mkdir -p "$R"
    "$PY" -I "$EVAL" analyze \
        --sets "$BASESETS,20261020-pubpy-h26-c2/sets_pubpy_halpe26_c2.json.gz,20261020-fit3d-h26A-c2/sets_fit3d_halpeA.json.gz" \
        --pose2d halpe26 --run-dir "$R" > "$R/log.txt" 2>&1
fi
echo "$(date -Is) ALLDONE $R"

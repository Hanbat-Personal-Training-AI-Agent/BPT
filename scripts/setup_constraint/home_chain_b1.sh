#!/bin/bash
# Home chain B1 (tuning subjects only): grid selection, tuning evaluation, foot shifts, quality signals.
# usage: home_chain_b1.sh CODE_DIR   (after the tuning occlusion XS of chain A)
set -u
C=$1; PY=~/miniconda3/envs/bpt-home/bin/python; E="$PY $C/scripts/eval_setup_constraint.py"
R="--root $HOME/datasets/fit3d --replay $HOME/bpt-smpl/replay --threads 4"; TU="--subjects s03,s04,s05 --cams 50591643,60457274"
echo "== tune $(date)"; $E tune $R --run-dir 20261020-tune $TU --jobs 4 2>&1 | grep -v Warn | tail -14
P=$($PY -c "import json;b=json.load(open('20261020-tune/tune.json'));print(json.dumps(b['best']['params']))")
AL=$($PY -c "import json;b=json.load(open('20261020-tune/tune.json'))['baselines'];print(min((v,k) for k,v in b.items() if k in ('B0.3','B0.5','B0.7'))[1][1:])")
TH=$($PY -c "import json;print(json.loads('$P').get('reliable_conf',0.5))")
echo "params=$P ema_alpha=$AL lock_thr=$TH" | tee selected_params.txt
echo "== evaluate tuning $(date)"; $E evaluate $R --run-dir 20261020-eval-tuning $TU --params "$P" --ema-alpha $AL --lock-thr $TH --rules --tag tuning 2>&1 | grep -v Warn | tail -2
echo "== foot-shift tuning $(date)"; $E foot-shift $R --run-dir 20261020-foot-shift-tuning $TU --params "$P" --ema-alpha $AL --lock-thr $TH --tag tuning --cases grad5,occ_grad5 2>&1 | grep -v Warn | tail -2
echo "== signals tuning $(date)"; $E signals $R --run-dir 20261020-signals-tuning $TU --tag tuning 2>&1 | grep -v Warn | tail -20
echo "== done B1 $(date)"

#!/bin/bash
# Home chain B (ai/setup-constraint): tuning selection -> tuning / validation evaluation, foot shifts, signals, setup E1.
# usage: home_chain_b.sh CODE_DIR   (run from ~/bpt-runs/setup-constraint, after chain A)
set -u
C=$1; PY=~/miniconda3/envs/bpt-home/bin/python; E="$PY $C/scripts/eval_setup_constraint.py"
R="--root $HOME/datasets/fit3d --replay $HOME/bpt-smpl/replay --threads 4"
TU=s03,s04,s05; HO=s07,s08,s09,s10,s11
echo "== tune $(date)"; $E tune $R --run-dir 20261020-tune --subjects $TU --cams 50591643,60457274 --jobs 4 2>&1 | grep -v Warn | tail -14
P=$($PY -c "import json;b=json.load(open('20261020-tune/tune.json'));print(json.dumps(b['best']['params']))")
AL=$($PY -c "import json;b=json.load(open('20261020-tune/tune.json'))['baselines'];print(min((v,k) for k,v in b.items() if k.startswith('B0.') or k in ('B0.3','B0.5','B0.7'))[1][1:])")
TH=$($PY -c "import json;print(json.loads('$P').get('reliable_conf',0.5))")
echo "params=$P ema_alpha=$AL lock_thr=$TH"
echo "== evaluate tuning $(date)"; $E evaluate $R --run-dir 20261020-eval-tuning --subjects $TU --cams 50591643,60457274 --params "$P" --ema-alpha $AL --lock-thr $TH --rules --tag tuning 2>&1 | grep -v Warn | tail -2
echo "== evaluate heldout $(date)"; $E evaluate $R --run-dir 20261020-eval-heldout --subjects $HO --params "$P" --ema-alpha $AL --lock-thr $TH --rules --tag heldout 2>&1 | grep -v Warn | tail -2
echo "== foot-shift heldout $(date)"; $E foot-shift $R --run-dir 20261020-foot-shift-heldout --subjects $HO --params "$P" --ema-alpha $AL --lock-thr $TH --tag heldout 2>&1 | grep -v Warn | tail -2
echo "== foot-shift tuning $(date)"; $E foot-shift $R --run-dir 20261020-foot-shift-tuning --subjects $TU --cams 50591643,60457274 --params "$P" --ema-alpha $AL --lock-thr $TH --tag tuning --cases grad5,occ_grad5 2>&1 | grep -v Warn | tail -2
echo "== signals $(date)"; $E signals $R --run-dir 20261020-signals-tuning --subjects $TU --cams 50591643,60457274 --tag tuning 2>&1 | grep -v Warn | tail -20
$E signals $R --run-dir 20261020-signals-heldout --subjects $HO --tag heldout 2>&1 | grep -v Warn | tail -3
echo "== xs-relations $(date)"; $E xs-relations $R --run-dir 20261020-e0b-xs-relations --subjects $TU,$HO 2>&1 | grep -v Warn | tail -30
echo "== setup-measure $(date)"; $E setup-measure $R --run-dir 20261020-e1-setup-measure --subjects $TU,$HO --shapes $HOME/bpt-runs/lift-refine/20261020-shapes-fit3d 2>&1 | grep -v Warn | tail -3
echo "== done B $(date)"

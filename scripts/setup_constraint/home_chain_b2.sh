#!/bin/bash
# Home chain B2 (validation subjects, ONE run with the parameters chosen in B1): evaluation, foot shifts, signals,
# XS relation stability, setup measurement. usage: home_chain_b2.sh CODE_DIR   (after chain A and B1)
set -u
C=$1; PY=~/miniconda3/envs/bpt-home/bin/python; E="$PY $C/scripts/eval_setup_constraint.py"
R="--root $HOME/datasets/fit3d --replay $HOME/bpt-smpl/replay --threads 4"; HO="--subjects s07,s08,s09,s10,s11"
read -r line < selected_params.txt; P=$(echo "$line" | sed -E 's/^params=(.*) ema_alpha=.*/\1/'); AL=$(echo "$line" | sed -E 's/.* ema_alpha=([^ ]+) .*/\1/'); TH=$(echo "$line" | sed -E 's/.* lock_thr=(.*)$/\1/')
echo "params=$P ema_alpha=$AL lock_thr=$TH"
echo "== evaluate heldout $(date)"; $E evaluate $R --run-dir 20261020-eval-heldout $HO --params "$P" --ema-alpha $AL --lock-thr $TH --rules --tag heldout 2>&1 | grep -v Warn | tail -2
echo "== foot-shift heldout $(date)"; $E foot-shift $R --run-dir 20261020-foot-shift-heldout $HO --params "$P" --ema-alpha $AL --lock-thr $TH --tag heldout 2>&1 | grep -v Warn | tail -2
echo "== verdicts $(date)"; $E verdicts --run-dir 20261020-verdicts --eval-json 20261020-eval-heldout/evaluate_heldout.json --shift-json 20261020-foot-shift-heldout/foot_shift_heldout.json --group heldout 2>&1 | grep -v Warn | tail -30
echo "== signals heldout $(date)"; $E signals $R --run-dir 20261020-signals-heldout $HO --tag heldout 2>&1 | grep -v Warn | tail -3
echo "== xs-relations $(date)"; $E xs-relations $R --run-dir 20261020-e0b-xs-relations --subjects s03,s04,s05,s07,s08,s09,s10,s11 2>&1 | grep -v Warn | tail -30
echo "== setup-measure $(date)"; $E setup-measure $R --run-dir 20261020-e1-setup-measure --subjects s03,s04,s05,s07,s08,s09,s10,s11 --shapes $HOME/bpt-runs/lift-refine/20261020-shapes-fit3d-val 2>&1 | grep -v Warn | tail -3
echo "== gt-relations all $(date)"; $E gt-relations --root $HOME/datasets/fit3d --run-dir 20261020-e0-gt-relations-all --subjects s03,s04,s05,s07,s08,s09,s10,s11 2>&1 | grep -v Warn | tail -3
echo "== done B2 $(date)"

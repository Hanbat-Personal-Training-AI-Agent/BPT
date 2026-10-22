#!/bin/bash
# Home chain A (ai/setup-constraint): tuning (2 cams) and validation (4 cams) occlusion XS in parallel (each computes
# and caches its own clean rows); then the clean cache for the remaining videos (E1 / E0b need every camera).
# usage: home_chain_a.sh CODE_DIR   (run from ~/bpt-runs/setup-constraint)
set -u
C=$1; PY=~/miniconda3/envs/bpt-home/bin/python; E="$PY $C/scripts/eval_setup_constraint.py"
R="--root $HOME/datasets/fit3d --replay $HOME/bpt-smpl/replay --threads 4"
echo "== occlude tuning + heldout (parallel) $(date)"
$E occlude $R --run-dir 20261020-occlude-tuning --subjects s03,s04,s05 --cams 50591643,60457274 > occlude-tuning.log 2>&1 &
$E occlude $R --run-dir 20261020-occlude-heldout --subjects s07,s08,s09,s10,s11 > occlude-heldout.log 2>&1 &
wait
grep -v Warn occlude-tuning.log | tail -11; grep -v Warn occlude-heldout.log | tail -11
echo "== cache-clean rest $(date)"; $E cache-clean $R --run-dir 20261020-cache-clean-rest --subjects s03,s04,s05,s07,s08,s09,s10,s11 2>&1 | grep -v Warn | tail -2
echo "== done A $(date)"

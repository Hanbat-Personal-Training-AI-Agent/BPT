#!/bin/bash
# Home chain A (ai/setup-constraint): finish the clean cache, then tuning occlusion, then validation occlusion.
# usage: home_chain_a.sh CODE_DIR   (run from ~/bpt-runs/setup-constraint)
set -u
C=$1; PY=~/miniconda3/envs/bpt-home/bin/python; E="$PY $C/scripts/eval_setup_constraint.py"
R="--root $HOME/datasets/fit3d --replay $HOME/bpt-smpl/replay --threads 4"
echo "== cache-clean $(date)"; $E cache-clean $R --run-dir 20261020-cache-clean-resume --subjects s03,s04,s05,s07,s08,s09,s10,s11 2>&1 | grep -v Warn | tail -2
echo "== occlude tuning $(date)"; $E occlude $R --run-dir 20261020-occlude-tuning-resume --subjects s03,s04,s05 --cams 50591643,60457274 2>&1 | grep -v Warn | tail -12
echo "== occlude heldout $(date)"; $E occlude $R --run-dir 20261020-occlude-heldout --subjects s07,s08,s09,s10,s11 2>&1 | grep -v Warn | tail -12
echo "== done A $(date)"

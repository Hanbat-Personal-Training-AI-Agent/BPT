#!/bin/bash
# Home chain C (ai/setup-constraint): method 2 RGB occlusion on a validation subset (15 videos, wrist/ankle/knee x 2 long).
# usage: home_chain_c.sh CODE_DIR PARAMS_JSON EMA_ALPHA LOCK_THR   (run from ~/bpt-runs/setup-constraint)
set -u
C=$1; P=$2; AL=$3; TH=$4
LC=$HOME/bpt-runs/lift-compare
V=""; for x in s07:50591643 s08:58860488 s09:60457274 s10:65906101 s11:50591643; do s=${x%%:*}; c=${x##*:}; for e in squat pushup barbell_row; do V="$V,${s}_${c}_${e}"; done; done; V=${V#,}
echo "== rgb mask $(date)"
~/miniconda3/envs/bpt-mmpose/bin/python $C/scripts/eval_setup_rgb_occlusion.py --root $HOME/datasets/fit3d --pose2d $LC/A-pose2d-20261019/pose2d \
  --out 20261020-rgb-mask/rgb --coco-cfg $LC/_code/da6d7f6/models/rtmpose/rtmpose-m_8xb256-420e_coco-256x192.py \
  --coco-ckpt $HOME/models/rtmpose_ft/src/rtmpose-m_simcc-coco_pt-aic-coco_420e-256x192-d8dd5ca4_20230127.pth --videos $V 2>&1 | grep -v -i warn | tail -16
echo "== rgb eval $(date)"
~/miniconda3/envs/bpt-home/bin/python $C/scripts/eval_setup_constraint.py rgb-eval --root $HOME/datasets/fit3d --replay $HOME/bpt-smpl/replay --threads 4 \
  --run-dir 20261020-rgb-eval --subjects s07,s08,s09,s10,s11 --rgb 20261020-rgb-mask/rgb --pose2d $LC/A-pose2d-20261019/pose2d \
  --params "$P" --ema-alpha $AL --lock-thr $TH --tag heldout 2>&1 | grep -v Warn | tail -12
echo "== done C $(date)"

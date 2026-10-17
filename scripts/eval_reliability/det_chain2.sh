#!/bin/bash
cd ~/bpt-runs/eval-reliability
PY=~/miniconda3/envs/bpt-mmpose/bin/python
flock ~/.bpt-gpu.lock $PY tools/det_crops.py det/mmfit_ref_exact clips/ref_exact/*.mp4 > det/mmfit_ref_exact.log 2>&1
todo=$(for v in $(cat inputs/public_held_side.txt); do s=$(basename $v .mp4); [ -f det/public_held_side/${s}_det.csv ] || echo $v; done)
flock ~/.bpt-gpu.lock $PY tools/det_crops.py det/public_held_side $todo > det/public_held_side2.log 2>&1
echo DET_DONE > det/det.done

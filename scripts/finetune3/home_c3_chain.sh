#!/bin/bash
# finetune3 C3 = Halpe26-only XS (plan §1.3, after D-F3-07). Waits for the 2D selection (rtm26_post) and for the 2D source
# decision file c3-2d-source.txt ("h26ft" when the Halpe26 candidate passed its 2D rule, else "base"; written after the
# Mac app-path checks; after 4 h without it the ORIGINAL m Halpe26 is used and logged). Re-exports Fit3D 2D with that model
# (lift-compare stage-1 RTMDet boxes), refits the Halpe offsets / residual pool, builds Halpe-mapped R / V / E, trains C3,
# and evaluates it ONCE (C3 on Halpe-mapped inputs; ft-repro / C1 / C2 on the same 2D with the app mapping). GPU lock.
set -euo pipefail
F=~/bpt-runs/finetune3; SHA=${SHA:?}; C=$F/_code/$SHA; PM=~/miniconda3/envs/bpt-mmpose/bin/python; PH=~/miniconda3/envs/bpt-home/bin/python
L=$F/c3_chain.log; X=$C/scripts/finetune3/xs_data.py; R=$F/c3-data; mkdir -p $R
trap 'rc=$?; echo "$(date) FAILED line $LINENO exit $rc" >> "$L"; exit "$rc"' ERR
export MPLCONFIGDIR=/tmp/ft3_mpl XDG_CACHE_HOME=/tmp/ft3_xdg
until grep -qs ALLDONE $F/rtm26_post.log; do sleep 60; done
t0=$(date +%s); until [ -f $F/c3-2d-source.txt ] || [ $(( $(date +%s) - t0 )) -gt 14400 ]; do sleep 60; done
SRC=$(cat $F/c3-2d-source.txt 2>/dev/null || echo base); SEL=$(grep -o "selected .*" $F/rtm26_post.log | head -1 | awk '{print $2}')
if [ "$SRC" = h26ft ] && [ -f "$SEL/rtm.pth" ]; then TAG=h26ft; SPEC=m_halpe26:$SEL/rtm.pth; E_CSV=$F/apppath/app_h26ft/e3d__cur
else TAG=base_h26; SPEC=m_halpe26; E_CSV=~/bpt-runs/reacquire/e3d__cur; fi
[ -f $F/c3-2d-source.txt ] || echo "$(date) no c3-2d-source.txt after 4 h: original m Halpe26 used" >> $L
echo "$(date) C3 2D source $TAG ($SPEC), Exercise3D CSVs $E_CSV" >> $L
# 1. Fit3D experiment-A 2D with that model (raw 26 keypoints) + app-mapped held-out sequences
for grp in s03,s04,s05 s07,s08,s09,s10,s11; do
  (cd $C/scripts && flock ~/.bpt-gpu.lock $PM finetune3/rtm_lift_effect.py --pose2d ~/bpt-runs/lift-compare/A-pose2d-20261019/pose2d --subjects $grp --models $TAG=$SPEC --box-tag rtmdet --save-raw $R/raw --out-dir $R/seq_${grp%%,*} >> $L 2>&1)
done
RAW=$R/raw/$TAG
# 2. Halpe offsets + residual pool (tuning subjects / Exercise3D P1), Halpe-mapped and app-mapped sets
cd $R
$PH $X offsets --halpe --pose2d $RAW --out offsets_h.json >> $L 2>&1
$PH $X pool --halpe --offsets offsets_h.json --pose2d $RAW --ex3d-csv $E_CSV --e-model halpe26 --out pool_h.npz >> $L 2>&1
$PH $X build --kinds A --pose2d $RAW --a-sources halpe --mapping halpe --a-tag C3 --subjects s03,s04,s05 --out A_train_hmap.npz >> $L 2>&1
$PH $X build --kinds V --subjects s03,s05 --offsets offsets_h.json --pool pool_h.npz --seed 0 --out V_s03s05_hmap.npz >> $L 2>&1
$PH $X build --kinds V --subjects s04 --offsets offsets_h.json --pool pool_h.npz --seed 1 --out V_s04_hmap.npz >> $L 2>&1
$PH $X build --kinds E --e-model halpe26 --mapping halpe --ex3d-csv $E_CSV --out E_P1_hmap.npz >> $L 2>&1
$PH $X build --kinds A --pose2d $RAW --a-sources halpe --mapping halpe --a-tag C3 --subjects s07,s08,s09,s10,s11 --out A_held_hmap.npz >> $L 2>&1
$PH $X build --kinds A --pose2d $RAW --a-sources halpe --a-tag C3 --subjects s07,s08,s09,s10,s11 --out A_held_app.npz >> $L 2>&1
G="--subjects s07,s08,s09,s10,s11 --exercises squat,pushup,diamond_pushup,barbell_row,barbell_dead_row --offsets offsets_h.json --pool pool_h.npz --noisy-only"
$PH $X vgrid $G --out Vgrid_held_hmap.npz >> $L 2>&1
$PH $X vgrid $G --v-mapping app --out Vgrid_held_app.npz >> $L 2>&1
$PH $X build --kinds E --eval-only --ex3d-seqs squat_0002,barbellrow_0003,barbellrow_0001 --e-model halpe26 --mapping halpe --ex3d-csv $E_CSV --out E_held_hmap.npz >> $L 2>&1
$PH $X build --kinds E --eval-only --ex3d-seqs squat_0002,barbellrow_0003,barbellrow_0001 --e-model halpe26 --ex3d-csv $E_CSV --out E_held_app.npz >> $L 2>&1
$PH $C/scripts/finetune3/manifest.py $R --commit $SHA --cmd "c3_chain.sh data (TAG=$TAG, E_CSV=$E_CSV)" --note "C3 data: Fit3D-derived (non-commercial) + Exercise3D (Sapiens2-derived)" --inputs $C/scripts/finetune3 >> $L 2>&1
# 3. train C3 (C1 / C2 recipe)
XS=~/models/MotionAGFormer/checkpoint/motionagformer-xs-h36m.pth.tr; T=$F/xs-C3; mkdir -p $T
cmd="$PH $C/scripts/finetune3/xs_train.py --data $R/A_train_hmap.npz $R/V_s03s05_hmap.npz $R/V_s04_hmap.npz $R/E_P1_hmap.npz --stride R=3,V=6,E=6 --out $T/xs.pth"
echo "$(date) start xs-C3" >> $L
if flock ~/.bpt-gpu.lock $cmd > $T/log.txt 2>&1; then
  $PH $C/scripts/finetune3/manifest.py $T --commit $SHA --cmd "flock ~/.bpt-gpu.lock $cmd" --note "finetune3 XS C3 (Halpe26-only, Halpe pelvis/neck/head mapping; 2D $TAG). NON-COMMERCIAL" --inputs $R/A_train_hmap.npz $R/V_s03s05_hmap.npz $R/V_s04_hmap.npz $R/E_P1_hmap.npz $C/scripts/finetune3 $XS >> $L 2>&1
else mv $T ${T}-FAILED-$(date +%H%M); echo "$(date) C3 FAILED" >> $L; exit 1; fi
echo "$(date) end xs-C3" >> $L
# 4. evaluate once: C3 on Halpe-mapped held-out sets, ft-repro / C1 / C2 on the same 2D with the app mapping
B1=~/bpt-runs/lift-compare/ft-repro-trains05-tests03/xs_ft_trains05.pth
E=$F/xs-final-C3; mkdir -p $E
flock ~/.bpt-gpu.lock $PH $C/scripts/finetune3/xs_eval.py --data $R/A_held_hmap.npz $R/Vgrid_held_hmap.npz $R/E_held_hmap.npz --models C3=$T/xs.pth --out $E/eval_c3.json >> $L 2>&1
flock ~/.bpt-gpu.lock $PH $C/scripts/finetune3/xs_eval.py --data $R/A_held_app.npz $R/Vgrid_held_app.npz $R/E_held_app.npz --models ftr05=$B1,C1=$F/xs-C1/xs.pth,C2=$F/xs-C2/xs.pth --out $E/eval_app.json >> $L 2>&1
for j in eval_c3 eval_app; do $PH $C/scripts/finetune3/xs_eval.py --table $E/$j.json --by kind,src,noise,bucket > $E/${j}_table.md 2>> $L; done
$PH $C/scripts/finetune3/manifest.py $E --commit $SHA --cmd "xs_eval C3 (hmap) / ftr05,C1,C2 (app) on c3-data held-out sets" --note "C3 single held-out look" --inputs $R/A_held_hmap.npz $R/A_held_app.npz $R/Vgrid_held_hmap.npz $R/Vgrid_held_app.npz $R/E_held_hmap.npz $R/E_held_app.npz $T/xs.pth >> $L 2>&1
echo "$(date) ALLDONE" >> $L

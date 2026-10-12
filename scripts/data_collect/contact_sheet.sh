#!/bin/sh
# Contact sheet for hand labelling: FPS frames/s, each tile stamped with its time (s), 1200 px wide.
# usage: contact_sheet.sh <video> <out.jpg> [fps=3] [start_s] [dur_s]
set -e
FF=${FFMPEG:-ffmpeg}; FP=${FFPROBE:-ffprobe}
v=$1; out=$2; fps=${3:-3}; ss=${4:-0}; t=${5:-}
wh=$($FP -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$v")
w=${wh%,*}; h=${wh#*,}
if [ "$w" -gt "$h" ]; then cols=6; else cols=10; fi
tw=$((1200 / cols))
d=$($FP -v error -show_entries format=duration -of csv=p=0 "$v")
[ -n "$t" ] && d=$t
n=$(python3 -c "import math;print(math.ceil(($d-$ss)*$fps) if $ss<$d else math.ceil($d*$fps))")
rows=$(( (n + cols - 1) / cols ))
$FF -v error -y -ss "$ss" ${t:+-t "$t"} -i "$v" -vf "fps=$fps,scale=$tw:-2,drawtext=text='%{eif\:t+$ss\:d}.%{eif\:10*(t+$ss)-10*trunc(t+$ss)\:d}':x=2:y=2:fontsize=14:fontcolor=yellow:box=1:boxcolor=black@0.6,tile=${cols}x${rows}:padding=2" -frames:v 1 -q:v 4 "$out"

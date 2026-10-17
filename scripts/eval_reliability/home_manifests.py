"""Write manifest.json into each Home analysis dir of ~/bpt-runs/eval-reliability (clips variants, label audits, det, ana):
file sha256s, the exact command line that produced it, tool sha256s, ffmpeg/x264 versions, original input sha256s.
usage: python3 -I home_manifests.py   (run on Home)"""
import hashlib, json, os, pathlib, subprocess, time
B = pathlib.Path.home() / "bpt-runs/eval-reliability"
DS = pathlib.Path.home() / "datasets/mmfit"
FF9 = str(pathlib.Path.home() / "miniconda3/envs/bpt-data/bin/ffmpeg")


def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    return h.hexdigest()


orig = {}
if (DS / "sha256.txt").exists():
    for line in open(DS / "sha256.txt"):
        h, p = line.split(); orig[p] = h
md5 = {l.split()[0]: l.split()[2] for l in open(DS / "pdl.log") if "OK" in l}
tools = {p.name: sha(p) for p in sorted((B / "tools").glob("*")) if p.is_file()}
ffv = subprocess.run([FF9, "-version"], capture_output=True, text=True).stdout.splitlines()[0]
common = {"created": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "host": "Home (WSL2)", "tools_sha256": tools,
          "originals": {"zenodo_record": 7672767, "md5_verified_against_zenodo": md5, "sha256": orig,
                        "labels_zip": "https://s3.eu-west-2.amazonaws.com/vradu.uk/mm-fit.zip"},
          "eval_pushup_mmfit_py": "tools/eval_pushup_mmfit.py = git show 1a8a3c4:scripts/eval_pushup_mmfit.py (identical to 2ef3ced)"}
L, R = "~/datasets/mmfit/ext/mm-fit", "~/datasets/mmfit/rgb"
CMDS = {
    "clips/mac_http_ff812": ("Mac: python3 -I py/cut_held.py scriptcopy labels/mm-fit clips_mac_http_a (Mac ffmpeg 8.1.2 Homebrew, x264 core 165 r3222, Zenodo HTTP); rsync to Home", "Mac ffmpeg 8.1.2"),
    "clips/mac_http_ff812_repeat": ("Mac: same command into clips_mac_http_b, stopped after 4 clips (determinism check: 4/4 byte-identical)", "Mac ffmpeg 8.1.2"),
    "clips/home_http_ff902": (f"PATH=~/miniconda3/envs/bpt-data/bin:$PATH python -I tools/cut_held.py tools {L} clips/home_http_ff902", ffv),
    "clips/home_local_ff902": (f"PATH=...bpt-data/bin:$PATH python -I tools/cut_held.py tools {L} clips/home_local_ff902 {R}", ffv),
    "clips/ref_exact": (f"python -I tools/make_ref.py tools {L} {R} clips/ref_exact {FF9}", ffv),
    "clips/tune_home_http_ff902": (f"PATH=...bpt-data/bin:$PATH python -I tools/cut_tune.py tools {L} clips/tune_home_http_ff902", ffv),
    "mmfit_label_audit": (f"~/miniconda3/envs/bpt-home/bin/python -I mmfit_label_audit.py {L} mmfit_label_audit/result.json", ""),
    "fit3d_repann_audit": ("PATH=...bpt-data/bin:$PATH ~/miniconda3/envs/bpt-home/bin/python -I fit3d_repann_audit.py ~/datasets/fit3d/train fit3d_repann_audit/result.json", ""),
    "det/ex3d_held": ("flock ~/.bpt-gpu.lock ~/miniconda3/envs/bpt-mmpose/bin/python tools/det_crops.py det/ex3d_held inputs/ex3d_held/*.mp4 (RTMDet-m rtmdet_m_8xb32-300e_coco_20220719_112220-229f527c.pth, mmdet 3.3.0, GTX 1060)", ""),
    "det/mmfit_ref_exact": ("flock ~/.bpt-gpu.lock .../python tools/det_crops.py det/mmfit_ref_exact clips/ref_exact/*.mp4", ""),
    "det/public_held_side": ("flock ~/.bpt-gpu.lock .../python tools/det_crops.py det/public_held_side $(cat inputs/public_held_side.txt) (two passes: tools/det_chain.sh, then tools/det_chain2.sh for the rest)", ""),
    "ana": ("RANGE=400 python -I tools/pose2d_offset.py <mm-fit> <mm-fit> mmfit_held_macA_own_bin2ef3ced mcoco17 ana/pose2d_offset_macA_coco.json; RANGE=60 ... halpe26 ana/pose2d_offset_macA_halpe.json; python -I tools/box_verify.py mmfit det/mmfit_ref_exact <mm-fit> ana/pose2d_offset_macA_coco.json ana/box_verify_mmfit_ref.json", ""),
    "inputs/ex3d_held": ("scp from Mac outputs/exercise3d_synced/<ex>/<seq>/<cam>.mp4 (renamed <seq>_<cam>.mp4, unchanged bytes)", ""),
}
for d, (cmd, ver) in CMDS.items():
    p = B / d
    if not p.exists(): continue
    files = {f.name: sha(f) for f in sorted(p.iterdir()) if f.is_file() and f.name != "manifest.json"}
    m = dict(common, dir=d, command=cmd, encoder=ver, files=files)
    json.dump(m, open(p / "manifest.json", "w"), indent=1)
    print(d, len(files))

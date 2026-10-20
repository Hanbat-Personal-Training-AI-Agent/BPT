"""finetune3 app-path (experiment B) runs on the Mac with the reacquire track's tooling unchanged (run.py / score.py /
sway.py in the shared scratchpad: pose-replay build 0d4724c, same clips, same configs), redirected to <scratch>/ft3/app so
the reacquire outputs and its Home folder are never written. Baseline 'mcoco17' (the app's RTMPose-m COCO17 package, same
binary) is linked from the reacquire 'cur' / 'det' outputs instead of re-run.

usage (Mac, bpt-eval):
  apppath.py run   <ds> <cfg> <tag> <mlpackage>      ds = fake | e3dkeep | e3d | mmfit | public ; cfg = cur | det
  apppath.py link  <ds> <cfg>                        baseline mcoco17 links
  apppath.py score <ds> <cfg> <tag,...>
  apppath.py boxes <ds> <raw_dir>                    RTMDet raw per-frame CSVs (det_crops.py) -> det/<ds>/online (prep_det.py rule)
Heavy pose-replay calls go through lockf /tmp/bpt-heavy.lock (inside run.py).
"""
import json, os, subprocess, sys, time
from pathlib import Path

S0 = Path('/private/tmp/claude-501/-Users-6-month-github-06-month-hanbat-repositories-BPT/d083b446-4e06-45ed-8204-8c6e9f22bd1c/scratchpad')
F = S0 / 'ft3' / 'app'
sys.path.insert(0, str(S0))
import run as R  # noqa: E402
import score as SC  # noqa: E402

F.mkdir(parents=True, exist_ok=True)
for name in ('clips', 'mmfit_labels', 'bin', 'fit3d_views.json'):
    if (S0 / name).exists() and not (F / name).exists():
        (F / name).symlink_to(S0 / name)
R.S, SC.S, R.DET, R.HASHES = F, F, F / 'det', F / 'sha256_cache.json'


def manifest(out, ds, cfg, model, cmds, todo, reused):
    """run.manifest with the Home copy going to bpt-runs/finetune3/apppath/<ds>__<cfg> (not the reacquire folder)."""
    m = {"run_id": f"{ds}__{cfg}__{model}", "dataset": ds, "config": cfg, "model": model, "options": R.flags(cfg, ds),
         "git_commit": R.COMMIT, "pose_replay_binary": R.REPLAY, "pose_replay_sha256": R.sha(R.REPLAY),
         "model_path": R.MODELS[model], "model_sha256": R.sha(R.MODELS[model]),
         "inputs": {s: {"path": str(Path(v).resolve()), "sha256": R.sha(v)} for s, v, _ in todo},
         "reused_from_cur": reused, "commands": cmds, "finished": time.strftime("%Y-%m-%dT%H:%M:%S"),
         "note": "finetune3 app path; NON-COMMERCIAL model if Fit3D-derived"}
    if "det" in cfg:
        d = R.DET / ds / "online"
        m["det_boxes"] = {s: R.sha(d / f"{s}_det.csv") for s, _, _ in todo if (d / f"{s}_det.csv").exists()}
    json.dump(m, open(out / f"manifest_{model}.json", "w"), indent=1)
    r = subprocess.run(["ssh", "Home", f"mkdir -p bpt-runs/finetune3/apppath/{ds}__{cfg}"])
    if not r.returncode:
        subprocess.run(["rsync", "-a", f"{out}/", f"Home:bpt-runs/finetune3/apppath/{ds}__{cfg}/"])


R.manifest = manifest


def link(ds, cfg):
    src, dst = S0 / 'out' / ds / cfg, F / 'out' / ds / cfg
    dst.mkdir(parents=True, exist_ok=True)
    n = 0
    for p in src.glob('*_mcoco17*'):
        if not (dst / p.name).exists():
            (dst / p.name).symlink_to(p); n += 1
    keep = S0 / 'kp_keep' / cfg
    if keep.exists():
        (F / 'kp_keep' / cfg).mkdir(parents=True, exist_ok=True)
        for p in keep.glob('*_mcoco17.csv'):
            q = F / 'kp_keep' / cfg / p.name
            if not q.exists():
                q.symlink_to(p)
    print('linked', n, 'baseline files for', ds, cfg)


def boxes(ds, raw):
    """det_crops.py *_detonline.csv -> det/<ds>/online/<stem>_det.csv (the reacquire `det` config input)."""
    d = F / 'det' / ds / 'online'; d.mkdir(parents=True, exist_ok=True)
    n = 0
    for p in Path(raw).glob('*_detonline.csv'):
        (d / (p.name[:-len('_detonline.csv')] + '_det.csv')).write_text(p.read_text()); n += 1
    print(n, 'box files ->', d)


def main():
    cmd = sys.argv[1]
    if cmd == 'run':
        ds, cfg, tag, pkg = sys.argv[2:6]
        R.MODELS[tag] = pkg
        R.main(ds, cfg, tag)
    elif cmd == 'link':
        link(*sys.argv[2:4])
    elif cmd == 'score':
        ds, cfg, tags = sys.argv[2], sys.argv[3], sys.argv[4].split(',')
        for t in tags:
            rs, miss = SC.rows(ds, cfg, t)
            for sp in ('tune', 'held', '-'):
                sub = [r for r in rs if r['split'] == sp]
                if sub:
                    a = SC.acc(sub)
                    print(ds, cfg, t, sp, SC.cell(a), 'alarm', a['alarm'], f"sfb {a['sfb']} tl {a['tl']}",
                          'lost%', f"{a['lost'] / a['frames']:.1%}", 'missing', len(miss))
    elif cmd == 'boxes':
        boxes(*sys.argv[2:4])


if __name__ == '__main__':
    main()

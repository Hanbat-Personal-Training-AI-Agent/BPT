"""finetune3 app-path (experiment B) runs on the Mac with the reacquire track's tooling unchanged (run.py / score.py in the
shared scratchpad: pose-replay build 0d4724c, same clips, same configs), redirected so the reacquire outputs and its Home
folder are never written. Every variant gets its own root <scratch>/ft3/app_<tag> (pose-replay names outputs after the
keypoint layout, so two packages of one layout must not share a folder); `base` = links to the reacquire outputs of the
app's packages (m COCO17 and m Halpe26, same binary).

usage (Mac, bpt-eval):
  apppath.py link  <ds> <cfg>                               base: link the reacquire mcoco17 + halpe26 outputs
  apppath.py run   <ds> <cfg> <tag> <layout> <mlpackage> [--det DIR]   layout = mcoco17 | halpe26; --det = box dir for cfg det
  apppath.py score <ds> <cfg> <tag>:<layout>,...            e.g. base:halpe26,h26ft:halpe26
ds = fake | e3dkeep | e3d | mmfit | public ; cfg = cur | det. Heavy pose-replay calls go through lockf (inside run.py).
"""
import json, subprocess, sys, time
from pathlib import Path

S0 = Path('/private/tmp/claude-501/-Users-6-month-github-06-month-hanbat-repositories-BPT/d083b446-4e06-45ed-8204-8c6e9f22bd1c/scratchpad')
sys.path.insert(0, str(S0))
import run as R  # noqa: E402
import score as SC  # noqa: E402


def root(tag):
    F = S0 / 'ft3' / f'app_{tag}'
    F.mkdir(parents=True, exist_ok=True)
    for name in ('clips', 'mmfit_labels', 'bin', 'fit3d_views.json'):
        if (S0 / name).exists() and not (F / name).exists():
            (F / name).symlink_to(S0 / name)
    return F


def use(tag):
    F = root(tag)
    R.S, SC.S, R.DET, R.HASHES = F, F, F / 'det', F / 'sha256_cache.json'
    return F


def manifest(out, ds, cfg, model, cmds, todo, reused):
    """run.manifest, with the Home copy going to bpt-runs/finetune3/apppath/<tag>/<ds>__<cfg> (not the reacquire folder)."""
    m = {"run_id": f"{R.S.name}/{ds}__{cfg}__{model}", "dataset": ds, "config": cfg, "model": model, "options": R.flags(cfg, ds),
         "git_commit": R.COMMIT, "pose_replay_binary": R.REPLAY, "pose_replay_sha256": R.sha(R.REPLAY),
         "model_path": R.MODELS[model], "model_sha256": R.sha(R.MODELS[model]),
         "inputs": {s: {"path": str(Path(v).resolve()), "sha256": R.sha(v)} for s, v, _ in todo},
         "reused_from_cur": reused, "commands": cmds, "finished": time.strftime("%Y-%m-%dT%H:%M:%S"),
         "note": "finetune3 app path; NON-COMMERCIAL model if Fit3D-derived"}
    if "det" in cfg:
        d = R.DET / ds / "online"
        m["det_boxes"] = {s: R.sha(d / f"{s}_det.csv") for s, _, _ in todo if (d / f"{s}_det.csv").exists()}
    json.dump(m, open(out / f"manifest_{model}.json", "w"), indent=1)
    dst = f"bpt-runs/finetune3/apppath/{R.S.name}/{ds}__{cfg}"
    if not subprocess.run(["ssh", "Home", f"mkdir -p {dst}"]).returncode:
        subprocess.run(["rsync", "-a", f"{out}/", f"Home:{dst}/"])


R.manifest = manifest


def link(ds, cfg):
    F = use('base')
    src, dst = S0 / 'out' / ds / cfg, F / 'out' / ds / cfg
    dst.mkdir(parents=True, exist_ok=True)
    n = 0
    for model in ('mcoco17', 'halpe26'):
        for p in src.glob(f'*_{model}*'):
            if not (dst / p.name).exists():
                (dst / p.name).symlink_to(p); n += 1
    print('linked', n, 'baseline files for', ds, cfg)


def boxes(F, ds, raw):
    """det_crops.py *_detonline.csv -> <root>/det/<ds>/online/<stem>_det.csv (the reacquire `det` config input)."""
    d = F / 'det' / ds / 'online'; d.mkdir(parents=True, exist_ok=True)
    for p in Path(raw).glob('*_detonline.csv'):
        (d / (p.name[:-len('_detonline.csv')] + '_det.csv')).write_text(p.read_text())


def main():
    cmd = sys.argv[1]
    if cmd == 'link':
        link(*sys.argv[2:4])
    elif cmd == 'run':
        ds, cfg, tag, layout, pkg = sys.argv[2:7]
        F = use(tag)
        if '--det' in sys.argv:
            boxes(F, ds, sys.argv[sys.argv.index('--det') + 1])
        app_pkg = {'mcoco17': Path.home() / 'bpt-models/rtmpose_m_forward.mlpackage',
                   'halpe26': Path.home() / 'bpt-models/rtmpose_m_halpe26_forward.mlpackage'}[layout]
        if cfg != 'cur' and not (F / 'out' / ds / 'cur').exists():
            # --only-lost reuses this variant's own cur run: only the app's own package may borrow the base cur run
            assert Path(pkg).resolve() == app_pkg.resolve(), f'run {ds} cur with {tag} first'
            (F / 'out' / ds).mkdir(parents=True, exist_ok=True)
            (F / 'out' / ds / 'cur').symlink_to(S0 / 'ft3' / 'app_base' / 'out' / ds / 'cur')
        R.MODELS[layout] = pkg
        R.main(ds, cfg, layout, *(['--only-lost'] if cfg != 'cur' else []))
    elif cmd == 'score':
        ds, cfg = sys.argv[2], sys.argv[3]
        for spec in sys.argv[4].split(','):
            tag, layout = spec.split(':')
            use(tag)
            rs, miss = SC.rows(ds, cfg, layout)
            for sp in ('tune', 'held', '-'):
                sub = [r for r in rs if r['split'] == sp]
                if sub:
                    a = SC.acc(sub)
                    print(ds, cfg, tag, layout, sp, SC.cell(a), 'alarm', a['alarm'], f"sfb {a['sfb']} tl {a['tl']}",
                          'lost%', f"{a['lost'] / a['frames']:.1%}", 'missing', len(miss))


if __name__ == '__main__':
    main()

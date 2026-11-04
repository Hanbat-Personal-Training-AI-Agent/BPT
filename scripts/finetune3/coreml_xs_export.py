"""Core ML export + PyTorch parity for a fine-tuned MotionAGFormer-XS checkpoint (Mac, bpt-coreml).

Reuses scripts/export_motionagformer_xs_coreml.py unchanged (coreml_safe attention patch, fp16 then fp32, fixed
[1,27,17,3]) but points its checkpoint / output paths elsewhere so the app asset assets/coreml/motionagformer_xs.mlpackage
is never touched. Parity: the same windows through the PyTorch checkpoint (CPU, unpatched model) and the Core ML
package (computeUnits ALL and CPU_ONLY); reports max / mean |diff| and MPJPE-style mean joint distance of the
selected row (26 - lookahead 5), in model units and relative to the output's joint spread.

usage: coreml_ft_export.py --ckpt CKPT --mag-repo DIR --out PKG --windows WINDOWS.npz --report JSON
"""
import argparse, json, sys
from pathlib import Path
import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT / 'scripts')]
import motionagformer_coreml_safe as S  # noqa: E402
import export_motionagformer_xs_coreml as E  # noqa: E402


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--ckpt', required=True); p.add_argument('--mag-repo', required=True); p.add_argument('--out', required=True)
    p.add_argument('--windows', required=True); p.add_argument('--report', required=True)
    a = p.parse_args()
    S.REPO_DIR = Path(a.mag_repo); S.CONFIG_PATH = S.REPO_DIR / 'configs/h36m/MotionAGFormer-xsmall.yaml'; S.CHECKPOINT_PATH = Path(a.ckpt)
    E.OUTPUT_PATH = Path(a.out); E.FAILURE_PATH_SAFE = Path(a.out + '.failure.txt'); E.FAILURE_PATH_ORIGINAL = E.FAILURE_PATH_SAFE
    E.ROOT = Path(a.out).parent  # only used for printing relative paths
    assert not Path(a.out).exists(), 'refusing to overwrite'
    sys.argv = [sys.argv[0], '--export-mode', 'coreml_safe']
    rc = E.main()
    assert rc == 0, 'export failed'
    import coremltools as ct
    X = np.load(a.windows)['x'].astype(np.float32)  # [K,27,17,3]
    ref = S.load_xs_model().eval()
    with torch.no_grad():
        Pt = np.concatenate([ref(torch.from_numpy(X[i:i + 64])).numpy() for i in range(0, len(X), 64)])
    rep = dict(ckpt=a.ckpt, package=a.out, windows=int(len(X)), precision=ct.models.MLModel(a.out).user_defined_metadata.get('precision'))
    for cu in ('ALL', 'CPU_ONLY'):
        m = ct.models.MLModel(a.out, compute_units=getattr(ct.ComputeUnit, cu))
        Pc = np.concatenate([m.predict({E.INPUT_NAME: X[i:i + 1]})[E.OUTPUT_NAME] for i in range(len(X))])
        d = np.abs(Pc - Pt); sel = 26 - 5
        jd = np.linalg.norm((Pc - Pc[:, :, :1]) - (Pt - Pt[:, :, :1]), axis=-1)[:, sel]
        spread = np.linalg.norm(Pt[:, sel] - Pt[:, sel, :1], axis=-1).mean()
        rep[cu] = dict(max_abs=float(d.max()), mean_abs=float(d.mean()), sel_row_joint_dist_mean=float(jd.mean()),
                       sel_row_joint_dist_p99=float(np.percentile(jd, 99)), rel_to_joint_spread=float(jd.mean() / spread))
    json.dump(rep, open(a.report, 'w'), indent=1); print(json.dumps(rep, indent=1))


if __name__ == '__main__':
    main()

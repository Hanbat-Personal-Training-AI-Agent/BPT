"""Offline check of the body fit on local calibration bundles (separate ephemeral app, no R2, no auth).

    modal run eval_fit.py --bundles <dir with <name>/{manifest.json, view_*.jpg[, reference.json]}> --out out.json

Each bundle is fitted with every variant in VARIANTS. With reference.json (People Snapshot consensus
mesh, scripts/build_people_snapshot_calibration_bundles.py) the reference bone lengths and the
"height only" baseline (mean shape put onto the same height, no photo information) come back too.
"""
import json
import time
from pathlib import Path

import modal

from modal_app import fit_image, weights

app = modal.App("bpt-calibration-eval")
VARIANTS = {
    "current": {"beta_reg": 1e-3, "refine_beta": True},
    "weak_prior": {"beta_reg": 1e-5, "refine_beta": True},
    "converter_beta": {"beta_reg": 1e-3, "refine_beta": False},
}


@app.function(image=fit_image.add_local_python_source("modal_app"), gpu="L4", volumes={"/weights": weights}, timeout=30 * 60, max_containers=4)
def evaluate(name, manifest, photos, reference):
    import numpy as np

    import body
    import fitting

    global _fitter
    if "_fitter" not in globals():
        _fitter = fitting.Fitter()
    out = {"name": name}
    if reference:
        verts = np.asarray(reference["vertices"])
        out["reference"] = body.bone_lengths_cm(body.h36m_joints(verts, _fitter.j_regressor_h36m))
        mean = body.project_to_height(_fitter.v_template, _fitter.shapedirs, np.zeros(10),
                                      manifest["userHeightCm"] / 100)
        out["heightOnly"] = body.bone_lengths_cm(
            body.h36m_joints(body.shaped_vertices(_fitter.v_template, _fitter.shapedirs, mean),
                             _fitter.j_regressor_h36m))
    for variant, knobs in VARIANTS.items():
        _fitter.beta_reg, _fitter.refine_beta = knobs["beta_reg"], knobs["refine_beta"]
        started = time.perf_counter()
        try:
            r = _fitter(manifest, photos)
        except Exception as error:  # report, keep going
            out[variant] = {"error": getattr(error, "code", repr(error))}
            continue
        out[variant] = {"seconds": round(time.perf_counter() - started, 2), "smplBeta": r["smplBeta"],
                        "segments": r["boneLengthData"]["segments"], "quality": r["quality"],
                        **{k: r["debug"].get(k) for k in ("betaConverter", "betaBeforeHeight", "mhrHeightM", "timing")}}
    return out


@app.local_entrypoint()
def main(bundles: str, out: str = "eval_fit.json", only: str = ""):
    jobs = []
    for d in sorted(Path(bundles).iterdir()):
        if not (d / "manifest.json").exists() or (only and d.name not in only.split(",")):
            continue
        manifest = json.loads((d / "manifest.json").read_text())
        photos = {v["label"]: (d / v["file"]).read_bytes() for v in manifest["views"]}
        ref = json.loads((d / "reference.json").read_text()) if (d / "reference.json").exists() else None
        jobs.append((d.name, manifest, photos, ref))
    results = list(evaluate.starmap(jobs))
    Path(out).write_text(json.dumps(results, indent=1))
    print(f"wrote {out}: {len(results)} bundles")

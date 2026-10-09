"""Export RTMPose-s neural-network forward only to Core ML.

This converts a fixed-shape TorchScript trace of ``model.extract_feat +
model.head``. It intentionally excludes MMPose preprocessing, bbox/crop/affine
logic, SimCC decoding, video I/O, and Python data sample handling.
"""

import shutil
import sys
import traceback
from pathlib import Path

import numpy as np
import torch


ROOT = Path(__file__).resolve().parents[1]
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from rtmpose_s_coreml_common import (  # noqa: E402
    COREML_MODEL_PATH,
    INPUT_NAME,
    INPUT_SHAPE,
    OUTPUT_NAMES,
    TRACE_PATH,
    VARIANT,
    load_rtmpose_model,
    load_or_create_forward_input,
    trace_forward_model,
)


FAILURE_PATH = ROOT / "assets/coreml/rtmpose_s_coreml_conversion_failure.txt"


def main():
    COREML_MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
    failures = []
    try:
        traced = load_or_create_trace()
        traced.eval()
    except Exception:
        failure = f"=== trace load/create failure ===\n{traceback.format_exc()}"
        FAILURE_PATH.write_text(failure, encoding="utf-8")
        print("RTMPose-s trace load/create failed")
        print(f"failure log: {FAILURE_PATH.relative_to(ROOT)}")
        return 1

    for precision in ("fp16", "fp32"):
        try:
            mlmodel = convert_trace(traced, precision)
            mlmodel.user_defined_metadata["precision"] = precision
            mlmodel.user_defined_metadata["export_scope"] = "rtmpose_s_forward_only"
            mlmodel.user_defined_metadata["keypoints"] = VARIANT
            mlmodel.user_defined_metadata["source"] = "RTMPose-s model.extract_feat + model.head fixed [1,3,256,192]"
            if COREML_MODEL_PATH.exists():
                if COREML_MODEL_PATH.is_dir():
                    shutil.rmtree(COREML_MODEL_PATH)
                else:
                    COREML_MODEL_PATH.unlink()
            mlmodel.save(str(COREML_MODEL_PATH))
            if FAILURE_PATH.exists():
                FAILURE_PATH.unlink()
            print(f"Core ML conversion status: succeeded ({precision})")
            print(f"saved: {COREML_MODEL_PATH.relative_to(ROOT)}")
            return 0
        except Exception:
            failure = f"=== {precision} conversion failure ===\n{traceback.format_exc()}"
            failures.append(failure)
            print(f"Core ML conversion status: failed ({precision})")

    FAILURE_PATH.write_text("\n\n".join(failures), encoding="utf-8")
    print("Core ML conversion status: failed")
    print(f"failure log: {FAILURE_PATH.relative_to(ROOT)}")
    return 1


def load_or_create_trace():
    if TRACE_PATH.exists():
        return torch.jit.load(str(TRACE_PATH), map_location="cpu")

    model = load_rtmpose_model(device="cpu")
    input_tensor = load_or_create_forward_input()
    traced = trace_forward_model(model, input_tensor)
    TRACE_PATH.parent.mkdir(parents=True, exist_ok=True)
    traced.save(str(TRACE_PATH))
    return traced


def convert_trace(traced, precision):
    import coremltools as ct

    compute_precision = ct.precision.FLOAT16 if precision == "fp16" else ct.precision.FLOAT32
    return ct.convert(
        traced,
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS16,
        inputs=[ct.TensorType(name=INPUT_NAME, shape=INPUT_SHAPE, dtype=np.float32)],
        outputs=[ct.TensorType(name=name) for name in OUTPUT_NAMES],
        compute_precision=compute_precision,
    )


if __name__ == "__main__":
    raise SystemExit(main())

"""Run RTMPose-s forward (PyTorch or Core ML) on video frames and write decoded keypoints.

Same preprocessing for both backends (whole frame resized to 192x256, like the app's
workout path), so comparing the two JSONL files with
compare_coreml_pipeline_with_pytorch_rtmpose.py isolates the conversion error.

  BPT_RTMPOSE_VARIANT=halpe26 conda run -n bpt-ai python scripts/export_rtmpose_s_forward_jsonl.py --backend torch ...
  BPT_RTMPOSE_VARIANT=halpe26 conda run -n bpt-coreml python scripts/export_rtmpose_s_forward_jsonl.py --backend coreml ...
"""

import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from rtmpose_s_coreml_common import (  # noqa: E402
    COREML_MODEL_PATH,
    INPUT_NAME,
    INPUT_SIZE_WH,
    prepare_input_tensor_from_frame,
)

SPLIT_RATIO = 2.0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend", choices=("torch", "coreml"), required=True)
    parser.add_argument("--coreml-model", default=str(COREML_MODEL_PATH))
    parser.add_argument("--video", required=True)
    parser.add_argument("--max-frames", type=int, default=240)
    parser.add_argument("--output-jsonl", required=True)
    parser.add_argument("--output-npz", help="also save raw simcc_x/simcc_y")
    args = parser.parse_args()

    import cv2

    predict = make_predictor(args)
    cap = cv2.VideoCapture(args.video)
    rows, xs, ys = [], [], []
    while len(rows) < args.max_frames:
        ok, frame = cap.read()
        if not ok:
            break
        simcc_x, simcc_y = predict(prepare_input_tensor_from_frame(frame))
        keypoints = decode(simcc_x[0], simcc_y[0], frame.shape[1], frame.shape[0])
        rows.append({
            "frame_index": len(rows),
            "coco17_keypoints": keypoints[:17],
            "all_keypoints": keypoints,
        })
        xs.append(simcc_x)
        ys.append(simcc_y)
    cap.release()

    out = Path(args.output_jsonl)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8")
    if args.output_npz:
        np.savez_compressed(args.output_npz, simcc_x=np.concatenate(xs), simcc_y=np.concatenate(ys))
    print(f"{args.backend}: {len(rows)} frames, {len(rows[0]['all_keypoints'])} joints -> {out}")


def make_predictor(args):
    if args.backend == "coreml":
        import coremltools as ct

        model = ct.models.MLModel(args.coreml_model, compute_units=ct.ComputeUnit.ALL)

        def predict(tensor):
            out = model.predict({INPUT_NAME: tensor})
            return np.asarray(out["simcc_x"], "float32"), np.asarray(out["simcc_y"], "float32")

        return predict

    import torch
    from rtmpose_s_coreml_common import RTMPoseForwardOnly, load_rtmpose_model

    model = RTMPoseForwardOnly(load_rtmpose_model()).eval()

    def predict(tensor):
        with torch.no_grad():
            x, y = model(torch.from_numpy(tensor))
        return x.numpy(), y.numpy()

    return predict


def decode(simcc_x, simcc_y, image_w, image_h):
    """Argmax decode like SimCCDecoder.swift, then the app's direct-resize inverse."""
    in_w, in_h = INPUT_SIZE_WH
    keypoints = []
    for jx, jy in zip(simcc_x, simcc_y):
        ix, iy = int(np.argmax(jx)), int(np.argmax(jy))
        conf = float(min(jx[ix], jy[iy]))
        keypoints.append([ix / SPLIT_RATIO * image_w / in_w, iy / SPLIT_RATIO * image_h / in_h, conf])
    return keypoints


if __name__ == "__main__":
    raise SystemExit(main())

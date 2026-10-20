"""finetune3: RTMPose-m COCO17 (fine-tuned state_dict) -> Core ML, like the app's rtmpose_m_forward.mlpackage
(scripts/export_rtmpose_s_coreml.py: model.extract_feat + model.head, fixed [1,3,256,192], mlprogram iOS16, fp16 then fp32)
but written outside assets/ (the app bundle is never touched). Two steps because no single env has mmpose + coremltools:

  trace    (Home bpt-mmpose)  TorchScript trace + parity inputs: COCO val2017 person crops (not Fit3D) and the PyTorch
                              simcc outputs on them -> TRACE.pt, PARITY.npz
  convert  (Mac bpt-coreml)   trace -> mlpackage; parity on the same crops with computeUnits ALL and CPU_ONLY: keypoint
                              distance (input px, app decode = argmax / 2) median / p99 / max, confidence |diff|.
Fit3D-derived weights: NON-COMMERCIAL; delete Mac copies of the trace after conversion.

usage: coreml_rtm_export.py trace --ckpt CKPT --out TRACE.pt --parity PARITY.npz [--coco ~/datasets/coco] [--n 200]
       coreml_rtm_export.py convert --trace TRACE.pt --parity PARITY.npz --out PKG.mlpackage --report JSON
"""
import argparse, json, os, sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path[:0] = [str(HERE.parent.parent), str(HERE.parent)]
INPUT_NAME, OUTPUT_NAMES, INPUT_SHAPE = 'input_image', ('simcc_x', 'simcc_y'), (1, 3, 256, 192)


def decode(sx, sy):
    """app / mmpose SimCC decode: argmax / split ratio 2, confidence = min of the two maxima (pose2d_data.decode_simcc)."""
    from pose_feedback.body.pose2d_data import decode_simcc
    out = [decode_simcc(a, b) for a, b in zip(sx, sy)]
    return np.array([k for k, _ in out]), np.array([c for _, c in out])


def trace(a):
    import cv2, torch
    os.environ['BPT_RTMPOSE_VARIANT'] = 'm_coco17'
    from pose2d_ft_common import MEAN, STD, crop_box, load_model
    from pose_feedback.body.pose2d_data import box_to_center_scale
    from rtmpose_s_coreml_common import RTMPoseForwardOnly
    model = load_model('m_coco17', a.ckpt or None, device='cpu')
    ann = json.load(open(f'{a.coco}/annotations/person_keypoints_val2017.json'))
    imgs = {i['id']: i for i in ann['images']}
    people = [p for p in ann['annotations'] if p['num_keypoints'] >= 8 and not p['iscrowd']]
    people = [people[i] for i in np.random.default_rng(0).choice(len(people), a.n, replace=False)]
    X = []
    for p in people:
        im = cv2.cvtColor(cv2.imread(f"{a.coco}/val2017/{imgs[p['image_id']]['file_name']}"), cv2.COLOR_BGR2RGB)
        x, y, w, h = p['bbox']
        cr, _ = crop_box(im, *box_to_center_scale([x, y, x + w, y + h]))
        X.append(((cr.astype(np.float32) - MEAN) / STD).transpose(2, 0, 1))
    X = np.stack(X).astype(np.float32)
    fwd = RTMPoseForwardOnly(model).eval()
    with torch.no_grad():
        traced = torch.jit.trace(fwd, torch.from_numpy(X[:1]))
        outs = [fwd(torch.from_numpy(X[i:i + 32])) for i in range(0, len(X), 32)]
    sx = np.concatenate([o[0].numpy() for o in outs]); sy = np.concatenate([o[1].numpy() for o in outs])
    traced.save(a.out)
    np.savez(a.parity, x=X, simcc_x=sx, simcc_y=sy, ckpt=str(a.ckpt))
    print(a.out, X.shape)


def convert(a):
    import coremltools as ct
    import torch
    traced = torch.jit.load(a.trace, map_location='cpu').eval()
    assert not Path(a.out).exists(), 'refusing to overwrite'
    ml = None
    for prec in ('fp16', 'fp32'):
        try:
            ml = ct.convert(traced, convert_to='mlprogram', minimum_deployment_target=ct.target.iOS16,
                            inputs=[ct.TensorType(name=INPUT_NAME, shape=INPUT_SHAPE, dtype=np.float32)],
                            outputs=[ct.TensorType(name=n) for n in OUTPUT_NAMES],
                            compute_precision=ct.precision.FLOAT16 if prec == 'fp16' else ct.precision.FLOAT32)
            ml.user_defined_metadata.update(precision=prec, export_scope='rtmpose_m_forward_only', keypoints='m_coco17',
                                            source='finetune3 RTMPose-m COCO17 fine-tune (NON-COMMERCIAL: Fit3D-derived)')
            ml.save(a.out); break
        except Exception as e:  # noqa: BLE001 — fp32 fallback like export_rtmpose_s_coreml.py
            print('conversion failed', prec, e)
    z = np.load(a.parity)
    kt, ct_ = decode(z['simcc_x'], z['simcc_y'])
    rep = dict(trace=a.trace, package=a.out, n=int(len(z['x'])), precision=ml.user_defined_metadata['precision'])
    for cu in ('ALL', 'CPU_ONLY'):
        m = ct.models.MLModel(a.out, compute_units=getattr(ct.ComputeUnit, cu))
        sx, sy = [], []
        for i in range(len(z['x'])):
            o = m.predict({INPUT_NAME: z['x'][i:i + 1]})
            sx.append(o['simcc_x'][0]); sy.append(o['simcc_y'][0])
        kc, cc = decode(np.array(sx), np.array(sy))
        d = np.linalg.norm(kc - kt, axis=-1)
        rep[cu] = dict(kp_px_median=float(np.median(d)), kp_px_p99=float(np.percentile(d, 99)), kp_px_max=float(d.max()),
                       conf_absdiff_mean=float(np.abs(cc - ct_).mean()))
    json.dump(rep, open(a.report, 'w'), indent=1); print(json.dumps(rep, indent=1))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['trace', 'convert'])
    p.add_argument('--ckpt', default=''); p.add_argument('--out', required=True); p.add_argument('--parity', required=True)
    p.add_argument('--coco', default=os.path.expanduser('~/datasets/coco')); p.add_argument('--n', type=int, default=200)
    p.add_argument('--trace'); p.add_argument('--report')
    a = p.parse_args()
    {'trace': trace, 'convert': convert}[a.cmd](a)


if __name__ == '__main__':
    main()

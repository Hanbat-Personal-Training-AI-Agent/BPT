"""eval-full: rules-calib `pubpy` (Python app path = LiveMotionAGFormer + Pose3DConstraints mirrors) with the XS input
built by the Halpe-own mapping (C3/C4: pelvis <- 19, thorax <- 18, head <- 17; = t4_halpe.py / xs_data.to_h36m).
Everything else is the rules-calib code unchanged: the 26-joint pose-replay CSV is read by read_csv_all, the app keeps
using its first 17 joints for the crop tracker validity, and only LiveMotionAGFormer._normalize sees the extra joints.

usage (Home): pubpy_halpe.py --rules-code ~/bpt-runs/rules-calib/_code/1682416 -- <eval_rules_calib.py pubpy args>
"""
import sys

import numpy as np


def main():
    i = sys.argv.index('--'); code = sys.argv[sys.argv.index('--rules-code') + 1]; rest = sys.argv[i + 1:]
    sys.path[:0] = [code, f'{code}/scripts']
    import eval_rules_calib as R
    from pose_feedback.body import live_motionagformer as LM
    from pose_feedback.body.motionagformer_adapter import (NORMALIZATION_LONG_SIDE, image_square_crop,
                                                           square_crop_normalize)
    cur = {'K26': None, 't': None}
    orig_read = R.read_csv_all

    def read_csv_all(path):
        K = orig_read(path); assert K.shape[1] == 26, (path, K.shape); cur['K26'] = K
        return K
    R.read_csv_all = read_csv_all

    orig_push = LM.LiveMotionAGFormer.push

    def push(self, frame, coco17, w, h, payload=None):
        cur['t'] = frame
        return orig_push(self, frame, coco17, w, h, payload)

    def _normalize(self, coco17, w, h):
        K = cur['K26'][cur['t']].astype('float64')
        assert np.allclose(K[:17], np.asarray(coco17, 'float64')), 'frame / CSV mismatch'
        xy, conf = LM.coco17_to_motionagformer_h36m17(K[None, :17])
        xy, conf = xy.copy(), conf.copy()
        for hj, j in ((19, 0), (18, 8), (17, 10)):
            xy[0, j], conf[0, j] = K[hj, :2], K[hj, 2]
        xy[0, 7] = (xy[0, 0] + xy[0, 8]) / 2; conf[0, 7] = (conf[0, 0] + conf[0, 8]) / 2
        xy[0, 9] = (K[0, :2] + xy[0, 8]) / 2; conf[0, 9] = (K[0, 2] + conf[0, 8]) / 2
        crop = self.tracker.update(xy[0], conf[0]) or image_square_crop(w, h, NORMALIZATION_LONG_SIDE)
        return np.concatenate([square_crop_normalize(xy[0], crop), conf[0][:, None]], axis=-1).astype('float32')

    LM.LiveMotionAGFormer.push = push
    LM.LiveMotionAGFormer._normalize = _normalize
    sys.argv = [sys.argv[0]] + rest
    R.main()


if __name__ == '__main__':
    main()

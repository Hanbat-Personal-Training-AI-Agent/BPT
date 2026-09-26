"""Causal person crop for the RTMPose front-end.

Per frame: keep the top-1 person detection above ``score_thr``, reject it if it
jumps away from the previous detection, and grow a running union of every
accepted box. The crop is that union, padded and fixed to the pose model's
aspect ratio, so the RTMPose input stays constant instead of jittering with
the detector.
"""


def box_iou(a, b):
    ix = max(0.0, min(a[2], b[2]) - max(a[0], b[0]))
    iy = max(0.0, min(a[3], b[3]) - max(a[1], b[1]))
    inter = ix * iy
    area = lambda z: (z[2] - z[0]) * (z[3] - z[1])
    return inter / (area(a) + area(b) - inter + 1e-9)


class PersonCropTracker:
    # ponytail: the union never shrinks; call reset() on exercise start/restart
    # or when the camera moves, otherwise the crop grows to cover every past position.
    def __init__(self, score_thr=0.5, min_iou=0.5, padding=1.25, aspect_wh=192 / 256):
        self.score_thr = score_thr
        self.min_iou = min_iou
        self.padding = padding
        self.aspect_wh = aspect_wh
        self.reset()

    def reset(self):
        self.union = None
        self.prev_box = None

    def update(self, detections):
        """detections: iterable of (x1, y1, x2, y2, score). Returns (accepted_box or None, crop or None)."""
        best = max((d for d in detections if d[4] >= self.score_thr), key=lambda d: d[4], default=None)
        box = tuple(best[:4]) if best is not None else None
        # A single-frame jump fails IoU against the previous raw box; a real move
        # is accepted one frame later because consecutive boxes agree again.
        accepted = box if box is not None and (
            self.prev_box is None or box_iou(box, self.prev_box) >= self.min_iou
        ) else None
        self.prev_box = box
        if accepted is not None:
            u = self.union
            self.union = accepted if u is None else (
                min(u[0], accepted[0]), min(u[1], accepted[1]),
                max(u[2], accepted[2]), max(u[3], accepted[3]),
            )
        return accepted, self.crop()

    def crop(self):
        """Padded union with fixed aspect ratio (may extend past the image; pad when warping)."""
        if self.union is None:
            return None
        x1, y1, x2, y2 = self.union
        cx, cy = (x1 + x2) / 2, (y1 + y2) / 2
        w, h = (x2 - x1) * self.padding, (y2 - y1) * self.padding
        if w > h * self.aspect_wh:
            h = w / self.aspect_wh
        else:
            w = h * self.aspect_wh
        return (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)

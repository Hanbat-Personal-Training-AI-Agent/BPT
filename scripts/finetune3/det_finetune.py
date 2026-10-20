"""finetune3 det: fine-tune RTMDet-m COCO (the pipeline experiments' detector, D-F3-03) on Fit3D SMPL-X person boxes
(build_det_fit3d.py) mixed with COCO train2017 person images; evaluate person box AP and the pipeline's own pick.

  coco-subset  COCO instances json -> person-only json with N images (seed 0)
  train        mmdet/mmengine Runner from the stock rtmdet_m_8xb32-300e_coco.py: load the COCO checkpoint, keep the 80-class
               head (persons = class 0), stage-2 pipeline only (no mosaic / mixup), AdamW, short cosine schedule, EMA as stock,
               a checkpoint per epoch (no validation inside: selection is done by `eval` on the tuning subject + COCO guard).
  eval         person AP@[.5:.95] / AP50 / AP75 (pycocotools, category person only) and the pipeline pick: the box with the
               largest score x area among persons with score >= 0.2 (reacquire det_crops.py rule) -> hit rate IoU >= 0.5 /
               0.75, miss rate (no box), median IoU.
Weights trained on Fit3D are non-commercial (Fit3D and SMPL-X licences). Home only.

usage (Home, bpt-mmpose, GPU lock):
  det_finetune.py coco-subset --ann instances_train2017.json --n 6000 --out coco_person_train6k.json
  det_finetune.py train --fit3d-json s03.json,s04.json --fit3d-root DIR --coco-json coco_person_train6k.json
                  --coco-root ~/datasets/coco/train2017 --work-dir RUN [--epochs 2 --lr 1e-4 --batch 4]
  det_finetune.py eval --ann s05.json --img-root DIR --ckpts tag=CKPT[:CFG],... --out OUT.json
"""
import argparse, json, os, sys

import numpy as np

CFG = os.path.expanduser('~/miniconda3/envs/bpt-mmpose/lib/python3.10/site-packages/mmdet/.mim/configs/rtmdet/rtmdet_m_8xb32-300e_coco.py')
CKPT = os.path.expanduser('~/models/rtmpose_ft/src/rtmdet_m_8xb32-300e_coco_20220719_112220-229f527c.pth')


def coco_subset(a):
    d = json.load(open(a.ann))
    anns = [x for x in d['annotations'] if x['category_id'] == 1]
    ids = sorted({x['image_id'] for x in anns})
    if a.n:
        ids = sorted(np.random.default_rng(0).choice(ids, min(a.n, len(ids)), replace=False).tolist())
    keep = set(ids)
    json.dump(dict(images=[i for i in d['images'] if i['id'] in keep], annotations=[x for x in anns if x['image_id'] in keep],
                   categories=[c for c in d['categories'] if c['id'] == 1]), open(a.out, 'w'))
    print(len(keep), 'images')


def train(a):
    from mmengine.config import Config
    from mmengine.runner import Runner
    cfg = Config.fromfile(CFG)
    pipe = cfg.train_pipeline_stage2
    sets = [dict(type='CocoDataset', data_root='', ann_file=f, data_prefix=dict(img=a.fit3d_root + '/'),
                 filter_cfg=dict(filter_empty_gt=True, min_size=32), pipeline=pipe) for f in a.fit3d_json.split(',')]
    if a.coco_json:
        sets.append(dict(type='CocoDataset', data_root='', ann_file=a.coco_json, data_prefix=dict(img=a.coco_root + '/'),
                         filter_cfg=dict(filter_empty_gt=True, min_size=32), pipeline=pipe))
    cfg.train_dataloader = dict(batch_size=a.batch, num_workers=a.workers, persistent_workers=True, pin_memory=True,
                                sampler=dict(type='DefaultSampler', shuffle=True), batch_sampler=None,
                                dataset=dict(type='ConcatDataset', datasets=sets))
    cfg.train_cfg = dict(type='EpochBasedTrainLoop', max_epochs=a.epochs, val_interval=10 ** 6)
    cfg.val_dataloader = cfg.val_evaluator = cfg.val_cfg = None
    cfg.test_dataloader = cfg.test_evaluator = cfg.test_cfg = None
    cfg.optim_wrapper = dict(type='OptimWrapper', optimizer=dict(type='AdamW', lr=a.lr, weight_decay=0.05),
                             paramwise_cfg=dict(norm_decay_mult=0, bias_decay_mult=0, bypass_duplicate=True))
    cfg.param_scheduler = [dict(type='LinearLR', start_factor=1e-3, by_epoch=False, begin=0, end=300),
                           dict(type='CosineAnnealingLR', eta_min=a.lr * 0.05, begin=0, end=a.epochs, T_max=a.epochs,
                                by_epoch=True, convert_to_iter_based=True)]
    cfg.custom_hooks = [h for h in cfg.custom_hooks if h['type'] == 'EMAHook']
    cfg.default_hooks.checkpoint = dict(type='CheckpointHook', interval=1, max_keep_ckpts=a.epochs)
    cfg.default_hooks.logger = dict(type='LoggerHook', interval=50)
    cfg.load_from = CKPT
    cfg.work_dir = a.work_dir
    cfg.randomness = dict(seed=0)
    cfg.auto_scale_lr = dict(enable=False, base_batch_size=256)
    os.makedirs(a.work_dir, exist_ok=True)
    cfg.dump(os.path.join(a.work_dir, 'det_cfg.py'))
    Runner.from_cfg(cfg).train()


def iou(a, b):
    x0, y0, x1, y1 = max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3])
    i = max(0, x1 - x0) * max(0, y1 - y0)
    return i / ((a[2] - a[0]) * (a[3] - a[1]) + (b[2] - b[0]) * (b[3] - b[1]) - i + 1e-9)


def evaluate(a):
    import cv2
    from mmdet.apis import inference_detector, init_detector
    from pycocotools.coco import COCO
    from pycocotools.cocoeval import COCOeval
    gt = COCO(a.ann)
    img_ids = sorted(gt.getImgIds(catIds=[1]))[::a.every]
    out = {}
    for spec in a.ckpts.split(','):
        tag, rest = spec.split('=', 1)
        ck, _, cfgp = rest.partition(':')
        model = init_detector(cfgp or CFG, ck, device='cuda:0' if not a.cpu else 'cpu')
        dets, picks = [], []
        for s in range(0, len(img_ids), 8):
            ids = img_ids[s:s + 8]
            imgs = [cv2.imread(os.path.join(a.img_root, gt.imgs[i]['file_name'])) for i in ids]
            for i, r in zip(ids, inference_detector(model, imgs)):
                p = r.pred_instances
                keep = p.labels == 0
                B, S = p.bboxes[keep].cpu().numpy(), p.scores[keep].cpu().numpy()
                dets += [dict(image_id=i, category_id=1, bbox=[float(b[0]), float(b[1]), float(b[2] - b[0]), float(b[3] - b[1])],
                              score=float(sc)) for b, sc in zip(B[:100], S[:100])]
                g = [x['bbox'] for x in gt.loadAnns(gt.getAnnIds(imgIds=i, catIds=[1], iscrowd=False))]
                ok = S >= 0.2
                if g and len(g) == 1:  # single-person images: the pipeline pick (largest score x area)
                    gb = [g[0][0], g[0][1], g[0][0] + g[0][2], g[0][1] + g[0][3]]
                    if ok.any():
                        k = np.argmax(S[ok] * (B[ok, 2] - B[ok, 0]) * (B[ok, 3] - B[ok, 1]))
                        picks.append(iou(B[ok][k], gb))
                    else:
                        picks.append(-1.0)
        res = {}
        if dets:
            E = COCOeval(gt, gt.loadRes(dets), 'bbox'); E.params.catIds = [1]; E.params.imgIds = img_ids
            E.evaluate(); E.accumulate(); E.summarize()
            res.update(AP=float(E.stats[0]), AP50=float(E.stats[1]), AP75=float(E.stats[2]), AR100=float(E.stats[8]))
        pk = np.array(picks)
        if len(pk):
            res.update(pick_n=int(len(pk)), pick_hit50=float((pk >= 0.5).mean()), pick_hit75=float((pk >= 0.75).mean()),
                       pick_miss=float((pk < 0).mean()), pick_iou_median=float(np.median(pk[pk >= 0])) if (pk >= 0).any() else None)
        res['images'] = len(img_ids)
        out[tag] = res
        print(tag, json.dumps(res), flush=True)
    json.dump(dict(ann=a.ann, ckpts=a.ckpts, every=a.every, results=out), open(a.out, 'w'), indent=1)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['coco-subset', 'train', 'eval'])
    p.add_argument('--ann'); p.add_argument('--n', type=int, default=0); p.add_argument('--out')
    p.add_argument('--fit3d-json'); p.add_argument('--fit3d-root'); p.add_argument('--coco-json'); p.add_argument('--coco-root')
    p.add_argument('--work-dir'); p.add_argument('--epochs', type=int, default=2); p.add_argument('--lr', type=float, default=1e-4)
    p.add_argument('--batch', type=int, default=4); p.add_argument('--workers', type=int, default=4)
    p.add_argument('--img-root'); p.add_argument('--ckpts'); p.add_argument('--every', type=int, default=1)
    p.add_argument('--cpu', action='store_true')
    a = p.parse_args()
    {'coco-subset': coco_subset, 'train': train, 'eval': evaluate}[a.cmd](a)


if __name__ == '__main__':
    main()

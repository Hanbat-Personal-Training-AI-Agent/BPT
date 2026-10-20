"""lift-refine studies on Fit3D mocap (Home only, aggregates only). Pre-registered rules: docs/results/lift_refine.md §0.

Original MotionAGFormer-XS on the app 2D (pose-replay RTMPose-m COCO17 CSVs), L=5; helpers from eval_lift_app_fit3d.py /
eval_lift_app_t2t3.py (same prep, cache, metrics, judge_py, two_d heights).

  constraints  every variant on the SAME raw XS rows: a03 = current default (a03ddd9: no knee clamp, squat knee
               reflection) / limits = anatomical_limits.json defaults (knee hyperextension clamp 15 deg) / calib =
               per-subject SAM 3D Body bone lengths (calib_subject_shapes.py, no height) / calib_h170 / oracle =
               mocap bone lengths of the subject (UPPER BOUND, not a product input) / prior = population ratios only /
               all_new = limits + calib / raw = no constraints. MPJPE, PA, accel, rep-extreme and ROM angle errors,
               bone-length CV and proportion error vs mocap, impossible-angle frames (definition D), invalid-joint
               frames, normal-rep false alarms of the current rules (judge_py, app 2D heights), and how often the same
               limits move the mocap pose itself.
  hands        MediaPipe Hand Landmarker (VIDEO, numHands 1, 0.5 thresholds = MediaPipeHandLandmarkerRunner) on the
               app's 256 px wrist crops (HandCropBuilder: wrist confidence >= 0.3, square clamped to the frame), all 21
               landmarks per side. Per-frame npz are Fit3D-derived: delete them after the wrist run.
  wrist        rtm / mp (= app: reject_crossed + 0.25 x forearm gate) / mp_dedupe (+ same-hand dedupe) / mp_raw (every
               detection, = the old overlay wrist): 2D wrist error vs projected mocap wrists, crossed rate (replaced
               wrist closer to the other mocap wrist), drawn-wrist crossed rate, XS 3D wrist error (rtm / mp / mp_dedupe).

usage (Home, bpt-home, code synced to ~/bpt-runs/lift-refine/_code/<sha>/):
  eval_lift_refine.py constraints --cpu --cache DIR --shapes RUN_SHAPES/subjects.json --root ~/datasets/fit3d --replay ~/bpt-smpl/replay --run-dir RUN
  eval_lift_refine.py hands --root ... --replay ... --task hand_landmarker.task --run-dir RUN [--jobs 6]
  eval_lift_refine.py wrist --cpu --cache DIR --hands RUN_HANDS/hands --root ... --replay ... --run-dir RUN
"""
import argparse, json, os, sys
from multiprocessing import Pool
from pathlib import Path
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eval_lift_app_fit3d as E  # noqa: E402
from eval_lift_app_fit3d import (ANG, EXERCISES, RULES_BY_EX, SIDES, angle_metrics, angles, apply_constraints, cat,  # noqa: E402
                                 finish, groups_of, knee_theta, load_model, load_seqs, pose_metrics, predict_rows,
                                 ref_angles, rep_records, rom_err, seq_key, st)
from eval_lift_app_t2t3 import two_d  # noqa: E402
from eval_3d_angles import interior  # noqa: E402

LIMBS = [('right_hip-right_knee', 1, 2), ('right_knee-right_ankle', 2, 3), ('left_hip-left_knee', 4, 5),
         ('left_knee-left_ankle', 5, 6), ('left_shoulder-left_elbow', 11, 12), ('left_elbow-left_wrist', 12, 13),
         ('right_shoulder-right_elbow', 14, 15), ('right_elbow-right_wrist', 15, 16)]
RATIOS = {'shin': ((2, 3), (5, 6)), 'upper_arm': ((11, 12), (14, 15)), 'forearm': ((12, 13), (15, 16))}  # / thigh


def limb_len(P, a, b): return np.linalg.norm(P[:, b] - P[:, a], axis=-1)


def ratios(P):
    """Per-frame segment / thigh ratios (L/R averaged): {shin, upper_arm, forearm} -> [N]."""
    thigh = (limb_len(P, 1, 2) + limb_len(P, 4, 5)) / 2
    return {k: (limb_len(P, *l) + limb_len(P, *r)) / 2 / np.maximum(thigh, 1e-9) for k, (l, r) in RATIOS.items()}


def impossible(P):
    """Definition D (literature, fixed before results): knee hyperextension > 15 deg, knee or elbow flexion > 160 deg."""
    bad = np.zeros(len(P), bool)
    for leg in SIDES:
        th = knee_theta(P, leg)[0]
        bad |= np.nan_to_num(th, nan=0) < -15
    for a, b, c in ((1, 2, 3), (4, 5, 6), (11, 12, 13), (14, 15, 16)):
        bad |= interior(P[:, a], P[:, b], P[:, c]) < 20
    return bad


def mocap_targets(G):
    """ORACLE: the subject's own mocap limb lengths (cm) from one sequence (Fit3D skeletons are constant per subject)."""
    return {n: float(np.median(limb_len(G, a, b)) * 100) for n, a, b in LIMBS}


def run_constraints(a):
    from pose_feedback.body.form_metrics_3d import UP
    model, dev = load_model(a); seqs = load_seqs(a)
    shapes = json.load(open(a.shapes)) if a.shapes else {}
    recs, reps = [], []
    for d in seqs:
        raw = predict_rows(model, dev, d['x'], [5], seq_key(d))[5]; mm = d['mm'][:, None, None] / 1000
        ref = ref_angles(d); side = {'L': 'left', 'R': 'right'}[d['side']]; G = d['G']
        td_app, td_gt = two_d(a, d); sq = d['ex'] == 'squat'
        old = dict(knee_clamp_deg=None, reflect_flipped_knee=sq)
        cal = shapes.get(d['subj'], {})
        variants = {'raw': None, 'a03': old, 'limits': dict(reflect_flipped_knee=sq), 'prior': dict(old, session_min_frames=10 ** 9),
                    'oracle': dict(old, calibration_targets_cm=mocap_targets(G))}
        if cal:
            variants.update(calib=dict(old, calibration_targets_cm=cal['segments_cm']),
                            calib_h170=dict(old, calibration_targets_cm=cal['segments_h170']),
                            all_new=dict(reflect_flipped_knee=sq, calibration_targets_cm=cal['segments_cm']))
        meta0 = dict(group=d['group'], exercise=d['ex'], subj=d['subj'], cam=d['cam'])
        for r in rep_records(G, d['seg'], d['ex'], side, UP, dict(meta0, var='mocap'), td_gt):
            reps.append(r)
        rg = ratios(G)
        for v, kw in variants.items():
            if kw is None:
                Q, rp = raw, [{'invalid_joints': []}] * len(raw)
            else:
                Q, rp = apply_constraints(raw, kw)
            P = (Q - Q[:, :1]) * mm
            inv = [r['invalid_joints'] for r in rp]
            Pm = P.copy()
            for i, j in enumerate(inv):
                if j: Pm[i, j] = np.nan
            rr = ratios(P)
            Lm = np.stack([limb_len(P, x, y) for _, x, y in LIMBS], 1) * 1000
            meta = dict(meta0, var=v)
            rec = dict(meta, impossible=impossible(P), invalid=np.array([bool(j) for j in inv]),
                       all17=np.array([len(j) == 17 for j in inv]),
                       bone_cv=np.median(Lm.std(0) / Lm.mean(0)),
                       prop_err=np.mean([abs(np.median(rr[k]) / np.median(rg[k]) - 1) for k in RATIOS]),
                       **pose_metrics(P, G), **angle_metrics(angles(P, d['side'], d['up_c']), ref, d['seg']),
                       rom=rom_err(angles(P, d['side'], d['up_c']), ref, d['seg']))
            if kw is not None:  # the same limits on the mocap pose (bone lengths off: mocap is its own length truth)
                _, rgp = apply_constraints(d['y'].astype(float), dict(kw, bone_lengths=False))
                rec['mocap_moved'] = np.array([bool(r['angle_corrections']) or r['knee_clamp_deg'] > 0 or r['knees_reflected'] > 0 for r in rgp])
                rec['mocap_invalid'] = np.array([bool(r['invalid_joints']) for r in rgp])
            recs.append(rec)
            for r in rep_records(Pm, d['seg'], d['ex'], side, UP, meta, td_app):
                reps.append(r)
        print(d['subj'], d['ex'], d['cam'], flush=True)
    f = lambda q, kk='p50': q.get(kk, float('nan'))
    summ = {'pose': {}, 'rules': {}}
    md = ['| 묶음 | 운동 | 변형 | 영상 | MPJPE | PA-MPJPE | 가속도 | ' + ' | '.join(f'{g} 렙극값 (p90)' for g in ('knee', 'hip', 'elbow', 'torso_g'))
          + ' | ROM 무릎 / 엉덩이 / 팔꿈치 / 몸통 | 뼈 CV | 비율 오차 | 불가능 각(D) | 무효 관절 프레임 | 모캡에서 움직임 / 무효 |', '|---' * 15 + '|']
    for k, rs in groups_of(recs, ('group', 'exercise', 'var')):
        s = dict(videos=len(rs), mpjpe=st(cat(rs, 'mpjpe')), pa=st(cat(rs, 'pa_mpjpe')), accel=st(cat(rs, 'accel')),
                 **{g: st(cat(rs, g, 'rep')) for g in ANG}, rom={g: st(cat(rs, 'rom', g)) for g in ('knee', 'hip', 'elbow', 'torso_g')},
                 bone_cv=float(np.median([r['bone_cv'] for r in rs])), prop_err=float(np.mean([r['prop_err'] for r in rs])),
                 impossible=float(cat(rs, 'impossible').mean()), invalid=float(cat(rs, 'invalid').mean()), all17=float(cat(rs, 'all17').mean()))
        if 'mocap_moved' in rs[0]:
            s.update(mocap_moved=float(cat(rs, 'mocap_moved').mean()), mocap_invalid=float(cat(rs, 'mocap_invalid').mean()))
        summ['pose']['/'.join(k)] = s
        mv = f"{s['mocap_moved']:.2%} / {s['mocap_invalid']:.2%}" if 'mocap_moved' in s else '-'
        rom = ' / '.join('%.1f' % f(s['rom'][g]) for g in ('knee', 'hip', 'elbow', 'torso_g'))
        md.append(f"| {k[0]} | {k[1]} | {k[2]} | {s['videos']} | {s['mpjpe']['mean']:.2f} | {s['pa']['mean']:.2f} | {s['accel']['mean']:.3f} | "
                  + ' | '.join(f"{f(s[g]):.2f} ({f(s[g], 'p90'):.0f})" for g in ('knee', 'hip', 'elbow', 'torso_g'))
                  + f" | {rom} | {s['bone_cv']:.2%} | {s['prop_err']:.1%} | {s['impossible']:.3%} | {s['invalid']:.2%} | {mv} |")
    variants = list(dict.fromkeys(r['var'] for r in reps))
    for ex in EXERCISES:
        rules = RULES_BY_EX[ex]
        md += ['', f'**{ex} 정상 렙 오경보 (현재 임계값, judge_py, 카메라 위, 2D 높이)**', '', '| 묶음 | 변형 | 렙 | ' + ' | '.join(rules) + ' |',
               '|---' * (3 + len(rules)) + '|']
        for grp in ('heldout', 'tuning'):
            for v in variants:
                rs = [r for r in reps if r['exercise'] == ex and r['group'] == grp and r['var'] == v]
                if not rs: continue
                fr = {q: round(float(np.mean([q in r['fired'] for r in rs])), 4) for q in rules}
                summ['rules'][f'{ex}/{grp}/{v}'] = dict(reps=len(rs), **fr)
                md.append(f"| {grp} | {v} | {len(rs)} | " + ' | '.join(f'{fr[q]:.1%}' for q in rules) + ' |')
    finish(a, 'constraints', summ, md, [d['csv'] for d in seqs] + [a.checkpoint] + ([a.shapes] if a.shapes else []))


# ---------------------------------------------------------------- hands with landmarks
def hand_job(job):
    video, K, task, out = job
    if os.path.exists(out): return out
    import cv2, mediapipe as mp
    from mediapipe.tasks.python import BaseOptions, vision
    mk = lambda: vision.HandLandmarker.create_from_options(vision.HandLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=task), running_mode=vision.RunningMode.VIDEO, num_hands=1,
        min_hand_detection_confidence=0.5, min_hand_presence_confidence=0.5, min_tracking_confidence=0.5))
    lms = {s: mk() for s in SIDES}
    res = np.full((len(K), 2, 21, 2), np.nan, np.float32)  # frame px
    n50 = int(cv2.VideoCapture(video).get(cv2.CAP_PROP_FRAME_COUNT))
    pick = np.round(np.arange(0, n50, 50 / 30)).astype(int)
    want = {int(f): i for i, f in enumerate(pick) if i < len(K)}
    cap = cv2.VideoCapture(video); f = 0
    while True:
        ok, fr = cap.read()
        if not ok: break
        i = want.get(f); f += 1
        if i is None: continue
        rgb = cv2.cvtColor(fr, cv2.COLOR_BGR2RGB); H, W = rgb.shape[:2]; size = int(min(256, W, H))
        for si, s in enumerate(SIDES):
            wx, wy, wc = K[i, E.COCO_WRIST[s]]
            if wc < 0.3: continue
            x0 = int(round(min(max(wx - size / 2, 0), W - size))); y0 = int(round(min(max(wy - size / 2, 0), H - size)))
            r = lms[s].detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=np.ascontiguousarray(rgb[y0:y0 + size, x0:x0 + size])),
                                        int(round(i * 1000 / 30)))
            if r.hand_landmarks:
                res[i, si] = [(x0 + p.x * size, y0 + p.y * size) for p in r.hand_landmarks[0]]
    for lm in lms.values(): lm.close()
    os.makedirs(os.path.dirname(out), exist_ok=True)
    np.save(out + '.tmp.npy', res); os.replace(out + '.tmp.npy', out)
    return out


def run_hands(a):
    from eval_3d_angles import fit3d_jobs, read_csv
    jobs, inputs = [], [a.task]
    for subj, ex, cam, J, R, T, ann, csv in fit3d_jobs(a.root, a.replay, a.subjects, a.exercises):
        K = read_csv(csv); n = min(len(K), len(J)); pick = np.round(np.arange(0, n, 50 / 30)).astype(int); pick = pick[pick < n]
        jobs.append((f'{a.root}/train/{subj}/videos/{cam}/{ex}.mp4', K[pick], a.task, f'{a.run_dir}/hands/{subj}/{cam}/{ex}.npy'))
        inputs.append(csv)
    print(len(jobs), 'videos', flush=True)
    with Pool(a.jobs) as p:
        for i, o in enumerate(p.imap_unordered(hand_job, jobs)): print(i, o, flush=True)
    E.write_manifest(a, inputs, [], dict(note='hands/*.npy = Fit3D-derived per-frame hand landmarks: delete after the wrist run'))


def run_wrist(a):
    from pose_feedback.body.pose2d_data import project_fit3d
    from pose_feedback.body.motionagformer_wrist_source import (build_motionagformer_input_2d, dedupe_same_hand,
                                                                gate_mediapipe_wrists, reject_crossed_mediapipe_wrists, same_hand)
    from finetune_motionagformer_fit3d import mag_input
    model, dev = load_model(a); seqs = load_seqs(a); recs = []
    for d in seqs:
        hp = f"{a.hands}/{d['subj']}/{d['cam']}/{d['ex']}.npy"
        if not os.path.exists(hp): continue
        Hd = np.load(hp); K, n = d['K'], len(d['K'])
        cam = json.load(open(f"{a.root}/train/{d['subj']}/camera_parameters/{d['cam']}/{d['ex']}.json"))
        Jp = d['J'][d['pick']]; gw = {s: project_fit3d(Jp[:, E.H_WRIST[s]], cam) for s in SIDES}
        _, crops0 = mag_input(K); ratio = d['mm'] / 1000 / (crops0[:, 2] / 2)
        G = d['G']; mm = d['mm'][:, None, None] / 1000
        for var in ('rtm', 'mp_raw', 'mp', 'mp_dedupe'):
            Kp = K.copy(); rep = np.zeros((n, 2), bool); same = np.zeros(n, bool)
            for i in range(n):
                found = {s: Hd[i, si, 0] for si, s in enumerate(SIDES) if np.isfinite(Hd[i, si, 0, 0])}
                same[i] = len(found) == 2 and same_hand(Hd[i, 0], Hd[i, 1])
                if var == 'rtm': continue
                kept = found if var == 'mp_raw' else gate_mediapipe_wrists(K[i], reject_crossed_mediapipe_wrists(
                    K[i], dedupe_same_hand(found, same[i]) if var == 'mp_dedupe' else found))
                Kp[i], _ = build_motionagformer_input_2d(K[i], kept, 'mediapipe')
                rep[i] = [s in kept for s in SIDES]
            e = {s: np.linalg.norm(Kp[:, E.COCO_WRIST[s], :2] - gw[s], axis=-1) for s in SIDES}
            other = {'left': 'right', 'right': 'left'}
            crossed = {s: np.linalg.norm(Kp[:, E.COCO_WRIST[s], :2] - gw[other[s]], axis=-1) < e[s] for s in SIDES}
            r = dict(group=d['group'], exercise=d['ex'], subj=d['subj'], cam=d['cam'], var=var, same=same,
                     w2d=np.concatenate([e[s] for s in SIDES]), replaced=rep.ravel(),
                     crossed_all=np.concatenate([crossed[s] for s in SIDES]),
                     crossed_rep=np.concatenate([crossed[s][rep[:, si]] for si, s in enumerate(SIDES)]))
            if var != 'mp_raw':
                x, crops = mag_input(Kp)
                Q = predict_rows(model, dev, x, [5], seq_key(d) if var == 'rtm' else None)[5]
                Q, _ = apply_constraints(Q, dict(knee_clamp_deg=None, reflect_flipped_knee=d['ex'] == 'squat'))
                P = (Q - Q[:, :1]) * (crops[:, 2] / 2 * ratio)[:, None, None]
                acc = lambda X: X[2:] - 2 * X[1:-1] + X[:-2]
                r.update(wrist3d=np.linalg.norm(P[:, [13, 16]] - G[:, [13, 16]], axis=-1).ravel() * 1000,
                         wrist_acc=np.linalg.norm(acc(P[:, [13, 16]]) - acc(G[:, [13, 16]]), axis=-1).ravel() * 1000,
                         elbow_ang=np.concatenate([np.abs(interior(P[:, s], P[:, el], P[:, w]) - interior(G[:, s], G[:, el], G[:, w]))
                                                   for s, el, w in ((11, 12, 13), (14, 15, 16))]),
                         mpjpe=pose_metrics(P, G)['mpjpe'])
            recs.append(r)
        print(d['subj'], d['ex'], d['cam'], flush=True)
    f = lambda q, kk='p50': q.get(kk, float('nan'))
    summ = {}
    md = ['| 묶음 | 운동 | 변형 | 영상 | 같은 손 프레임 | 교체 | 손목 2D 오차 중앙값 (p90) px | 교체 중 교차 | 그린 손목 교차(전체) | 손목 3D mm | 손목 가속도 | 팔꿈치각 ° | MPJPE |',
          '|---' * 13 + '|']
    for k, rs in groups_of(recs, ('group', 'exercise', 'var')):
        s = dict(videos=len(rs), same=float(cat(rs, 'same').mean()), replaced=float(cat(rs, 'replaced').mean()), w2d=st(cat(rs, 'w2d')),
                 crossed_rep=float(cat(rs, 'crossed_rep').mean()) if len(cat(rs, 'crossed_rep')) else 0.0,
                 crossed_all=float(cat(rs, 'crossed_all').mean()))
        if 'wrist3d' in rs[0]:
            s.update(wrist3d=st(cat(rs, 'wrist3d')), wrist_acc=st(cat(rs, 'wrist_acc')), elbow_ang=st(cat(rs, 'elbow_ang')), mpjpe=st(cat(rs, 'mpjpe')))
        summ['/'.join(k)] = s
        tail = (f"{s['wrist3d']['mean']:.1f} | {s['wrist_acc']['mean']:.2f} | {f(s['elbow_ang']):.1f} | {s['mpjpe']['mean']:.1f}"
                if 'wrist3d' in s else '- | - | - | -')
        md.append(f"| {k[0]} | {k[1]} | {k[2]} | {s['videos']} | {s['same']:.2%} | {s['replaced']:.1%} | {f(s['w2d']):.2f} ({f(s['w2d'], 'p90'):.1f}) | "
                  f"{s['crossed_rep']:.2%} | {s['crossed_all']:.2%} | {tail} |")
    finish(a, 'wrist', summ, md, [d['csv'] for d in seqs] + [a.checkpoint])


def main():
    p = argparse.ArgumentParser()
    p.add_argument('cmd', choices=['constraints', 'hands', 'wrist'])
    p.add_argument('--root'); p.add_argument('--replay'); p.add_argument('--run-dir', required=True)
    p.add_argument('--subjects', type=lambda s: s.split(','), default=['s07', 's08', 's09', 's10', 's11'])
    p.add_argument('--exercises', type=lambda s: s.split(','), default=list(EXERCISES))
    p.add_argument('--mag-repo', default=os.path.expanduser('~/models/MotionAGFormer'))
    p.add_argument('--checkpoint', default=None); p.add_argument('--cpu', action='store_true')
    p.add_argument('--cache', default=None); p.add_argument('--shapes', default=None)
    p.add_argument('--task'); p.add_argument('--hands'); p.add_argument('--jobs', type=int, default=6)
    a = p.parse_args()
    E.CACHE['dir'] = a.cache
    a.checkpoint = a.checkpoint or f'{a.mag_repo}/checkpoint/motionagformer-xs-h36m.pth.tr'
    os.makedirs(a.run_dir, exist_ok=True)
    {'constraints': run_constraints, 'hands': run_hands, 'wrist': run_wrist}[a.cmd](a)


if __name__ == '__main__':
    main()

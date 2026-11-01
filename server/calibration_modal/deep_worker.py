"""GVHMR → 반복 리포트 → 원본 위 3D 관절 투영 + 측면 패널 MP4."""
import json
import itertools
import time
import uuid
import os
import subprocess
import tempfile
import traceback
from pathlib import Path

import numpy as np

from checks import Rejected
from deep_analysis import frame_angles, metrics, verify_upload
from deep_metrics import COCO_ANGLE_JOINTS, TRUNK_JOINTS, finite_number

RUNTIME_INSTANCE = uuid.uuid4().hex
RUNTIME_JOB_ORDINAL = itertools.count(1)

BONES = [(0, 1), (1, 2), (2, 3), (0, 4), (4, 5), (5, 6), (0, 7), (7, 8), (8, 9), (9, 10),
         (8, 11), (11, 12), (12, 13), (8, 14), (14, 15), (15, 16)]


# H36M displayed joints depend on these observed COCO joints; central joints are inferred.
H36M_SUPPORT_JOINTS = [[11, 12], [12], [14], [16], [11], [13], [15], [5, 6, 11, 12],
                      [5, 6], [0, 5, 6], [0, 3, 4], [5], [7], [9], [6], [8], [10]]


def overlay_support(joint_support, tracked, frame):
    if tracked is None:
        return np.zeros(17, dtype=bool), "추적 정보 없음 · 보류"
    if not tracked[frame]:
        return np.zeros(17, dtype=bool), "추적 보간 · 보류"
    if joint_support is None:
        return np.zeros(17, dtype=bool), "관절 정보 없음 · 보류"
    valid = np.array([joint_support[frame, indices].min() >= .35 for indices in H36M_SUPPORT_JOINTS])
    return valid, "낮은 지지도 · 회색" if not valid.all() else "2D 검출 지지도"


def panel_lines(current, frame, angles, joint_support=None, tracked_mask=None):
    """Display only supported estimates; report values remain unchanged."""
    _, support_label = overlay_support(joint_support, tracked_mask, frame)
    lines = ["BPT 심층분석 · 3D 추정", support_label,
             f"{current['repIndex']}회" if current else "준비 / 반복 사이"]
    if not current:
        return lines
    side = current["side"]
    groups = dict(COCO_ANGLE_JOINTS[side], torso=TRUNK_JOINTS)
    primary = current.get("primaryJoint")
    groups.update(romDeg=groups.get(primary, []), tempoSeconds=groups.get(primary, []))

    def available(key):
        indices = groups[key]
        value = (current.get("romDeg") if key == "romDeg" else
                 current.get("tempoSeconds", {}).get("total") if key == "tempoSeconds" else
                 angles[side][key][frame])
        return (current.get("metricValidity", {}).get(key, {}).get("assessment") == "available"
                and finite_number(value)
                and tracked_mask is not None and bool(tracked_mask[frame])
                and joint_support is not None and bool(indices)
                and bool(np.all(np.isfinite(joint_support[frame, indices])))
                and bool(np.all(joint_support[frame, indices] >= .35)))

    for key, label in (("knee", "무릎"), ("hip", "고관절"), ("elbow", "팔꿈치"),
                       ("shoulder", "어깨"), ("torso", "몸통")):
        value = angles[side][key][frame]
        lines.append(f"{label} {value:.1f}°" if available(key) and np.isfinite(value)
                     else f"{label} 판정 보류")
    lines.append(f"가동 범위 {current['romDeg']:.1f}°" if available("romDeg")
                 else "가동 범위 판정 보류")
    lines.append(f"반복 시간 {current['tempoSeconds']['total']:.2f}초" if available("tempoSeconds")
                 else "반복 시간 판정 보류")
    # Comparison concerns only the report's assessed rules, not all pose estimates.
    comparison = current.get("comparison", "not_comparable")
    if not all(available(key) for key in groups):
        lines.append("평가 항목 비교 보류")
    else:
        lines.append({"agree": "평가 항목 일치", "different": "평가 항목 다름",
                      "not_comparable": "판정 비교 대상 아님"}.get(comparison, "평가 항목 비교 보류"))
    return lines


def command(args):
    return subprocess.run(args, check=True, capture_output=True, timeout=180).stdout


def normalize(source, target):
    # PTS 기준을 보존해 저 FPS 카메라 영상도 30 FPS로 복제한다. 잘라서 경계를 바꾸지 않는다.
    probe = json.loads(command(["ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(source)]))
    streams = [s for s in probe["streams"] if s["codec_type"] == "video"]
    if len(streams) != 1:
        raise Rejected(422, "video_unreadable")
    video = streams[0]
    duration = float(video.get("duration", probe["format"].get("duration", 0)))
    if not np.isfinite(duration) or not 1 <= duration <= 60.1:
        raise Rejected(422, "video_duration")
    if (max(video["width"], video["height"]) > 1280 or min(video["width"], video["height"]) > 720
            or video.get("codec_name") != "h264"):
        raise Rejected(422, "video_dimensions")
    command(["ffmpeg", "-v", "error", "-y", "-i", str(source), "-an", "-vf",
             "setpts=PTS-STARTPTS,fps=30,scale=1280:1280:force_original_aspect_ratio=decrease:force_divisible_by=2",
             "-c:v", "libx264", "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(target)])


def render(video, output, camera, world, intrinsic, report, joint_support=None, tracked_mask=None):
    import cv2
    from PIL import Image, ImageDraw, ImageFont

    cap = cv2.VideoCapture(str(video))
    width, height = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    # 원래 가로세로 비율을 보존하고 영상 오른쪽에 반투명 각도 패널을 겹친다.
    panel = max(200, int(width * .32))
    font_size = max(13, int(width / 48))
    font = ImageFont.truetype(os.environ.get("BPT_FONT", "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"), font_size)
    angles = {side: frame_angles(world, side) for side in ("left", "right")}
    process = subprocess.Popen(["ffmpeg", "-v", "error", "-y", "-f", "rawvideo", "-pix_fmt", "bgr24",
                                "-s", f"{width}x{height}", "-r", "30", "-i", "pipe:0", "-an",
                                "-c:v", "libx264", "-preset", "fast", "-crf", "22", "-pix_fmt", "yuv420p",
                                "-movflags", "+faststart", str(output)], stdin=subprocess.PIPE,
                               stderr=subprocess.DEVNULL)
    try:
        for i, joints in enumerate(camera):
            ok, frame = cap.read()
            if not ok:
                raise Rejected(422, "video_unreadable")
            uv = joints @ intrinsic.T
            valid = uv[:, 2] > 0.01
            uv = np.clip(uv[:, :2] / np.maximum(uv[:, 2:], 0.01), -10000, 10000).astype(int)
            supported, support_label = overlay_support(joint_support, tracked_mask, i)
            for a, b in BONES:
                if valid[a] and valid[b]:
                    color = (90, 240, 100) if supported[a] and supported[b] else (145, 145, 145)
                    cv2.line(frame, tuple(uv[a]), tuple(uv[b]), color, 3, cv2.LINE_AA)
            canvas = frame
            canvas[:, width - panel:] = (canvas[:, width - panel:] * .25).astype(np.uint8)
            current = next((r for r in report["reps"] if r["startMs"] <= i * 1000 / 30 < r["endMs"]), None)
            # world 좌표를 비스듬히 보여 주는 별도 3D 골격. 프레임마다 같은 축척을 쓴다.
            p = world[i] - world[i, 0]
            scale = min(panel * .3, height * .12)
            points = np.column_stack((width - panel / 2 + scale * (p[:, 0] + .55 * p[:, 2]),
                                      height - scale * 1.4 - scale * p[:, 1])).astype(int)
            for a, b in BONES:
                color = (90, 240, 100) if supported[a] and supported[b] else (145, 145, 145)
                cv2.line(canvas, tuple(points[a]), tuple(points[b]), color, 2, cv2.LINE_AA)
            image = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
            draw = ImageDraw.Draw(image)
            lines = panel_lines(current, i, angles, joint_support, tracked_mask)
            for y, line in enumerate(lines):
                draw.text((width - panel + 8, 12 + y * (font_size + 9)), line, font=font, fill="white")
            process.stdin.write(cv2.cvtColor(np.array(image), cv2.COLOR_RGB2BGR).tobytes())
        process.stdin.close()
        if process.wait(timeout=180) != 0:
            raise RuntimeError("overlay_encode_failed")
    finally:
        cap.release()
        if process.poll() is None:
            process.kill()
            process.wait()


def analyze(source, directory, m, progress, beta=None):
    import gvhmr_runner as runner

    analyze_started = time.perf_counter()
    phase_started = analyze_started
    timings = {}
    normalized = directory / "normalized.mp4"
    normalize(source, normalized)
    timings["normalizeVideo"] = round(time.perf_counter() - phase_started, 3)
    progress(15)
    phase_started = time.perf_counter()
    meta = runner.run(normalized, directory / "gvhmr", max_seconds=61, keep_video=True, beta=beta)
    timings["infer"] = round(time.perf_counter() - phase_started, 3)
    if meta["other_people"]:
        raise Rejected(422, "multiple_people")
    progress(75)
    phase_started = time.perf_counter()
    with np.load(directory / "gvhmr/result.npz", allow_pickle=False) as result:
        joint_support = np.clip(result["vitpose_coco17"][:, :, 2], 0, 1) * (meta["person_frames"] / meta["frames"])
        support = joint_support.mean(axis=1)
        tracked_mask = result["tracked_mask"] if "tracked_mask" in result else None
        report = metrics(result["h36m17_world"], 30, m, confidence=support,
                         joint_confidence=joint_support, tracked_mask=tracked_mask)
        report["timingSeconds"] = meta["timing_s"]
        report["runnerElapsedSeconds"] = meta.get("elapsed_s")
        absolute = meta.get("device_used_peak_mib", {})
        report["resourceUsage"] = {"deviceUsedPeakMiB": max(absolute.values(), default=None),
                                   "stageDeviceUsedPeakMiB": absolute,
                                   "stageDeltaMiB": meta.get("vram_peak_mib", {}),
                                   "samplingIntervalMs": meta.get("vram_sampling_interval_ms", 20),
                                   "measurement": "cuda_mem_get_info_total_minus_free_device_wide_sampled"}
        timings["metrics"] = round(time.perf_counter() - phase_started, 3)
        phase_started = time.perf_counter()
        output = directory / "overlay.mp4"
        render(directory / "gvhmr/input_30fps.mp4", output, result["h36m17_cam"], result["h36m17_world"], result["K"], report, joint_support=joint_support, tracked_mask=tracked_mask)
    timings["render"] = round(time.perf_counter() - phase_started, 3)
    progress(95)
    timings["analyze"] = round(time.perf_counter() - analyze_started, 3)
    report["processingTimingSeconds"] = timings
    return report, output


def run(job, bucket, state, analyze_video=analyze):
    key = f"deep-job:{job['jobId']}"
    worker_started = time.perf_counter()
    job_ordinal = next(RUNTIME_JOB_ORDINAL)
    worker_times = {}

    def progress(value):
        state.put(key, job | {"status": "running", "progressRate": value})

    try:
        progress(5)
        phase_started = time.perf_counter()
        m = verify_upload(bucket, job["prefix"], job["sizes"], job["sessionId"])
        worker_times["validateInput"] = round(time.perf_counter() - phase_started, 3)
        if m != job["manifest"]:
            raise Rejected(422, "invalid_reps")
        with tempfile.TemporaryDirectory(prefix="bpt-deep-") as temp:
            directory = Path(temp)
            source = directory / "video.mp4"
            phase_started = time.perf_counter()
            data = bucket.get(job["prefix"] + "video.mp4")
            if len(data) != job["sizes"]["video.mp4"]:
                raise Rejected(422, "invalid_file_size")
            source.write_bytes(data)
            worker_times["downloadInput"] = round(time.perf_counter() - phase_started, 3)
            phase_started = time.perf_counter()
            shape = job.get("shape") or {}
            report, output = analyze_video(source, directory, m, progress, shape.get("smplBeta"))
            worker_times["analyzeVideo"] = round(time.perf_counter() - phase_started, 3)
            report["runtime"] = {"instanceId": RUNTIME_INSTANCE, "jobOrdinal": job_ordinal,
                                 "firstJobInProcess": job_ordinal == 1, "modelLoadPolicy": "per_job",
                                 "scope": "worker_process_reuse_not_proof_of_modal_cold_or_warm_start"}
            # 체형 스캔 β가 없으면 GVHMR이 영상에서 추정한 체형으로 대신 계산했음을 남긴다.
            report["bodyShape"] = ({"source": "calibration", "calibrationJobId": shape["calibrationJobId"]}
                                   if shape else {"source": "gvhmr_fallback"})
            report_key = f"deep-results/{job['userId']}/{job['jobId']}/report.json"
            video_key = f"deep-results/{job['userId']}/{job['jobId']}/overlay.mp4"
            phase_started = time.perf_counter()
            bucket.put_json(report_key, report)
            bucket.put_bytes(video_key, output.read_bytes(), "video/mp4")
            worker_times["uploadArtifacts"] = round(time.perf_counter() - phase_started, 3)
        worker_times["total"] = round(time.perf_counter() - worker_started, 3)
        worker_timing = {"seconds": worker_times,
                         "scope": "entry_through_artifact_upload_and_cleanup_excluding_terminal_state_commit"}
        state.put(key, job | {"status": "done", "workerTiming": worker_timing, "progressRate": 100, "report": report,
                             "reportKey": report_key, "videoKey": video_key})
    except Exception as error:
        code = getattr(error, "code", "internal_error")
        state.put(key, job | {"status": "failed", "error": code})
        # 에러 원문에는 사용자 경로나 저장소 응답이 포함될 수 있으므로 앱에는 코드만, 원문은 서버 로그에만 남긴다.
        traceback.print_exc()
        return {"error": code}
    return {"status": "done"}

"""GVHMR → 반복 리포트 → 원본 위 3D 관절 투영 + 측면 패널 MP4."""
import json
import os
import subprocess
import tempfile
import traceback
from pathlib import Path

import numpy as np

from checks import Rejected
from deep_analysis import frame_angles, metrics, verify_upload

BONES = [(0, 1), (1, 2), (2, 3), (0, 4), (4, 5), (5, 6), (0, 7), (7, 8), (8, 9), (9, 10),
         (8, 11), (11, 12), (12, 13), (8, 14), (14, 15), (15, 16)]


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


def render(video, output, camera, world, intrinsic, report):
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
            for a, b in BONES:
                if valid[a] and valid[b]:
                    cv2.line(frame, tuple(uv[a]), tuple(uv[b]), (90, 240, 100), 3, cv2.LINE_AA)
            canvas = frame
            canvas[:, width - panel:] = (canvas[:, width - panel:] * .25).astype(np.uint8)
            current = next((r for r in report["reps"] if r["startMs"] <= i * 1000 / 30 < r["endMs"]), None)
            # world 좌표를 비스듬히 보여 주는 별도 3D 골격. 프레임마다 같은 축척을 쓴다.
            p = world[i] - world[i, 0]
            scale = min(panel * .3, height * .12)
            points = np.column_stack((width - panel / 2 + scale * (p[:, 0] + .55 * p[:, 2]),
                                      height - scale * 1.4 - scale * p[:, 1])).astype(int)
            for a, b in BONES:
                cv2.line(canvas, tuple(points[a]), tuple(points[b]), (90, 240, 100), 2, cv2.LINE_AA)
            image = Image.fromarray(cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB))
            draw = ImageDraw.Draw(image)
            lines = ["BPT 심층분석 · 3D 추정", f"{current['repIndex']}회" if current else "준비 / 반복 사이"]
            if current:
                side = current["side"]
                lines += [f"{label} {angles[side][key][i]:.1f}°" for key, label in
                          (("knee", "무릎"), ("hip", "고관절"), ("elbow", "팔꿈치"), ("shoulder", "어깨"), ("torso", "몸통"))]
                lines += [f"가동 범위 {current['romDeg']:.1f}°", f"반복 시간 {current['tempoSeconds']['total']:.2f}초",
                          {"agree": "기기와 일치", "different": "기기와 다름", "not_comparable": "판정 비교 대상 아님"}[current["comparison"]]]
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

    normalized = directory / "normalized.mp4"
    normalize(source, normalized)
    progress(15)
    meta = runner.run(normalized, directory / "gvhmr", max_seconds=61, keep_video=True, beta=beta)
    if meta["other_people"]:
        raise Rejected(422, "multiple_people")
    progress(75)
    with np.load(directory / "gvhmr/result.npz", allow_pickle=False) as result:
        support = np.clip(result["vitpose_coco17"][:, :, 2], 0, 1).mean(axis=1)
        support *= meta["person_frames"] / meta["frames"]
        report = metrics(result["h36m17_world"], 30, m, confidence=support)
        report["timingSeconds"] = meta["timing_s"]
        output = directory / "overlay.mp4"
        render(directory / "gvhmr/input_30fps.mp4", output, result["h36m17_cam"], result["h36m17_world"], result["K"], report)
    progress(95)
    return report, output


def run(job, bucket, state, analyze_video=analyze):
    key = f"deep-job:{job['jobId']}"

    def progress(value):
        state.put(key, job | {"status": "running", "progressRate": value})

    try:
        progress(5)
        m = verify_upload(bucket, job["prefix"], job["sizes"], job["sessionId"])
        if m != job["manifest"]:
            raise Rejected(422, "invalid_reps")
        with tempfile.TemporaryDirectory(prefix="bpt-deep-") as temp:
            directory = Path(temp)
            source = directory / "video.mp4"
            data = bucket.get(job["prefix"] + "video.mp4")
            if len(data) != job["sizes"]["video.mp4"]:
                raise Rejected(422, "invalid_file_size")
            source.write_bytes(data)
            shape = job.get("shape") or {}
            report, output = analyze_video(source, directory, m, progress, shape.get("smplBeta"))
            # 체형 스캔 β가 없으면 GVHMR이 영상에서 추정한 체형으로 대신 계산했음을 남긴다.
            report["bodyShape"] = ({"source": "calibration", "calibrationJobId": shape["calibrationJobId"]}
                                   if shape else {"source": "gvhmr_fallback"})
            report_key = f"deep-results/{job['userId']}/{job['jobId']}/report.json"
            video_key = f"deep-results/{job['userId']}/{job['jobId']}/overlay.mp4"
            bucket.put_json(report_key, report)
            bucket.put_bytes(video_key, output.read_bytes(), "video/mp4")
        state.put(key, job | {"status": "done", "progressRate": 100, "report": report,
                             "reportKey": report_key, "videoKey": video_key})
    except Exception as error:
        code = getattr(error, "code", "internal_error")
        state.put(key, job | {"status": "failed", "error": code})
        # 에러 원문에는 사용자 경로나 저장소 응답이 포함될 수 있으므로 앱에는 코드만, 원문은 서버 로그에만 남긴다.
        traceback.print_exc()
        return {"error": code}
    return {"status": "done"}

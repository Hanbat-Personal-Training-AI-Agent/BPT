// calib-rca: 앱의 CalibrationFrameAnalyzer + CalibrationEngine(심볼릭 링크)으로 영상을 재생하고
// 프레임마다 모든 관문 값을 CSV로 남긴다. docs/results/calib_root_cause.md 참고.
//
//   calib-rca [--hflip] [--pad-aspect W/H] [--zoom-out K] [--tilt-image DEG] [--rotate 0|90|180|270]
//             [--step N] [--roll DEG] [--set key=value]... <video> <out.csv>
//
// 입력 변환 순서: hflip → pad-aspect → zoom-out → tilt-image → rotate.
// --tilt-image 는 폰이 좌우로 DEG만큼 기운 장면을 흉내 낸다(가운데 기준 회전, 반시계 +, 바깥은 검정).
// --roll 은 엔진에 넘기는 폰 기울기 값(관문 확인용)이고 그림은 바꾸지 않는다.
// --rotate 는 버퍼가 돌아서 들어온 경우(연결 회전 미적용 등)를 흉내 낸다(시계 방향 각도).
// --zoom-out K 는 버퍼 화각이 미리보기보다 K배 넓은 경우를 흉내 낸다(가운데 1/K 크기, 나머지 검정).
// 폰 상태는 --roll 값 하나로 고정(흔들림 0). 촬영 저장은 항상 성공으로 처리한다.
import AVFoundation
import CoreImage
import CoreML
import Foundation

var rotate = 0, hflip = false, padAspect: Double?, zoomOut = 1.0, step = 1, rollDeg = 0.0, tiltImage = 0.0
var config = CalibrationConfig.default
var positional: [String] = []
var args = CommandLine.arguments.dropFirst().makeIterator()
func number(_ text: String?) -> Double {
    guard let text, let value = Double(text) else { print("number expected"); exit(2) }
    return value
}
while let arg = args.next() {
    switch arg {
    case "--rotate": rotate = Int(number(args.next()))
    case "--hflip": hflip = true
    case "--pad-aspect": padAspect = number(args.next())
    case "--zoom-out": zoomOut = number(args.next())
    case "--step": step = max(1, Int(number(args.next())))
    case "--roll": rollDeg = number(args.next())
    case "--tilt-image": tiltImage = number(args.next())
    case "--set":
        let kv = (args.next() ?? "").split(separator: "=").map(String.init)
        guard kv.count == 2, let v = Double(kv[1]) else { print("--set key=value"); exit(2) }
        switch kv[0] {
        case "minWristReach": config.aPose.minWristReach = v
        case "maxWristDrop": config.aPose.maxWristDrop = v
        case "minWristDrop": config.aPose.minWristDrop = v
        case "minElbowRatio": config.aPose.minElbowRatio = v
        case "maxElbowRatio": config.aPose.maxElbowRatio = v
        case "minAnkleGap": config.aPose.minAnkleGapOverHipWidth = v
        case "maxAnkleGap": config.aPose.maxAnkleGapOverHipWidth = v
        case "minBodyHeight": config.framing.minBodyHeight = v
        case "maxBodyHeight": config.framing.maxBodyHeight = v
        case "maxCentreOffset": config.framing.maxCentreOffset = v
        case "maxFeetDrift": config.stance.maxFeetDrift = v
        case "maxCentreDrift": config.stance.maxCentreDrift = v
        case "maxMotion": config.capture.maxMotionPerSecond = v
        case "holdDuration": config.capture.holdDuration = v
        case "maxRollDeg": config.device.maxRollDeg = v
        default: print("unknown key \(kv[0])"); exit(2)
        }
    default: positional.append(arg)
    }
}
guard positional.count == 2 else {
    print("usage: calib-rca [options] <video> <out.csv>")
    exit(2)
}

let repoRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let modelURL = repoRoot.appendingPathComponent("ios/Runner/NativePose/Models/\(RTMPoseModel.active.rawValue).mlpackage")
let configuration = MLModelConfiguration()
configuration.computeUnits = .all
let model = try MLModel(contentsOf: try MLModel.compileModel(at: modelURL), configuration: configuration)
let context = CIContext(options: [.cacheIntermediates: false])

func atOrigin(_ image: CIImage) -> CIImage {
    image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
}

func prepare(_ input: CIImage) -> CIImage {
    var image = atOrigin(input)
    if hflip { image = atOrigin(image.transformed(by: CGAffineTransform(scaleX: -1, y: 1))) }
    if let padAspect, image.extent.height * padAspect > image.extent.width {
        let width = (image.extent.height * padAspect).rounded()
        let canvas = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: width, height: image.extent.height))
        image = image.transformed(by: CGAffineTransform(translationX: ((width - image.extent.width) / 2).rounded(), y: 0))
            .composited(over: canvas)
    }
    if zoomOut > 1 {
        let size = image.extent.size, s = 1 / zoomOut
        let canvas = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        image = image.transformed(by: CGAffineTransform(scaleX: s, y: s))
            .transformed(by: CGAffineTransform(translationX: size.width * (1 - s) / 2, y: size.height * (1 - s) / 2))
            .composited(over: canvas)
    }
    if tiltImage != 0 {
        // A phone rolled by θ sees the scene rolled by -θ: rotate about the centre, keep the frame size.
        let extent = image.extent
        image = image.transformed(by: CGAffineTransform(translationX: -extent.midX, y: -extent.midY)
            .concatenating(CGAffineTransform(rotationAngle: tiltImage * .pi / 180))
            .concatenating(CGAffineTransform(translationX: extent.midX, y: extent.midY)))
            .composited(over: CIImage(color: .black).cropped(to: extent)).cropped(to: extent)
    }
    switch rotate {
    case 90: image = atOrigin(image.oriented(.right))
    case 180: image = atOrigin(image.oriented(.down))
    case 270: image = atOrigin(image.oriented(.left))
    default: break
    }
    return image
}

func f(_ value: Double?) -> String {
    guard let value, value.isFinite else { return "" }
    return String(format: "%.4f", value)
}

let video = URL(fileURLWithPath: positional[0])
let asset = AVURLAsset(url: video)
guard let track = asset.tracks(withMediaType: .video).first else { print("no video track"); exit(1) }
let reader = try AVAssetReader(asset: asset)
let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
])
reader.add(output)
reader.startReading()

let analyzer = try CalibrationFrameAnalyzer(model: model, context: context,
                                            minConfidence: config.framing.minKeypointConfidence)
let engine = CalibrationEngine(config: config)
var header = ["i", "t", "w", "h", "guidance", "classified", "candidate", "target", "hold", "pass", "captured",
              "motion", "faceDet", "faceYaw", "faceRel", "cropX", "cropY", "cropW", "cropH",
              "torso", "headTop", "feet", "bodyH", "midX", "wristDropL", "wristDropR", "elbowL", "elbowR",
              "wristReach", "ankleGap", "swT", "hwT", "noseOffset", "chest", "meanConf", "r", "delta"]
for j in 0..<17 { header += ["k\(j)x", "k\(j)y", "k\(j)s"] }
var lines = [header.joined(separator: ",")]
var index = -1
var captures: [String] = []
while let sample = output.copyNextSampleBuffer() {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
    index += 1
    guard index % step == 0 else { continue }
    let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
    let image = prepare(CIImage(cvPixelBuffer: pixelBuffer))
    guard let analysis = try? analyzer.analyze(image) else {
        analyzer.reset()
        engine.invalidateFrame()
        continue
    }
    let w = Double(analysis.imageSize.width), h = Double(analysis.imageSize.height)
    let device = CalibrationDeviceState(rollDeg: rollDeg, pitchDeg: 0, userAccelerationG: 0, rotationRateRadPerSec: 0,
                                        gravity: [0, -1, 0], isAvailable: true, timestamp: t)
    let frame = CalibrationFrame(
        keypoints: analysis.keypoints.map { CalibrationKeypoint(x: $0.x / w, y: $0.y / h, score: $0.confidence) },
        aspect: w / h, timestamp: t, device: device, face: analysis.face)
    let candidate = engine.viewCandidate(for: frame)
    var result = engine.process(frame)
    if let capture = result.capture, let resolved = engine.resolveCapture(id: capture.id, saved: true) {
        result = resolved
        captures.append(String(format: "%@@%.2f", capture.view.rawValue, t))
    }
    let m = result.measurement
    var row = [String(index), f(t), f(w), f(h), "\(result.guidance)", result.classifiedView?.rawValue ?? "",
               candidate?.rawValue ?? "", result.targetView?.rawValue ?? "", f(result.holdProgress),
               result.isPassing ? "1" : "0", result.capturedViews.map(\.rawValue).joined(separator: "|"),
               f(engine.lastMotion), analysis.face.isDetected ? "1" : "0", f(analysis.face.yawDeg),
               analysis.face.isReliable ? "1" : "0",
               f(analysis.crop.minX / w), f(analysis.crop.minY / h), f(analysis.crop.width / w), f(analysis.crop.height / h),
               f(m?.torso), f(m?.headTop), f(m?.feet), f(m?.bodyHeight), f(m?.midX),
               f(m?.leftWristDrop), f(m?.rightWristDrop), f(m?.leftElbowRatio), f(m?.rightElbowRatio),
               f(m?.wristReach), f(m?.ankleGapOverHipWidth), f(m.map { $0.shoulderWidth / $0.torso }),
               f(m.map { $0.hipWidth / $0.torso }), f(m?.noseOffset), m.map { $0.chestTowardsCamera ? "1" : "0" } ?? "",
               f(m?.meanRequiredConfidence), f(m.flatMap { engine.rValue($0) }), f(m.flatMap { engine.delta($0) })]
    for kp in frame.keypoints { row += [f(kp.x), f(kp.y), f(kp.score)] }
    lines.append(row.joined(separator: ","))
}
try (lines.joined(separator: "\n") + "\n").write(to: URL(fileURLWithPath: positional[1]), atomically: true, encoding: .utf8)
print("\(video.lastPathComponent): \(lines.count - 1) frames, captured: \(captures.isEmpty ? "none" : captures.joined(separator: " "))")

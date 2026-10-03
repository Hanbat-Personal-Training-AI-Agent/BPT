import CoreImage
import CoreML
import Foundation
import Vision

/// Per-frame perception for calibration: RTMPose-s keypoints plus a Vision face check.
///
/// RTMPose runs top-down on a 3:4 crop around where the person was in the previous frame,
/// so the body fills the 192×256 input at its trained scale and keeps its aspect ratio
/// (the shared full-image path stretches a portrait frame 1.33× sideways). With no
/// previous person it falls back to the whole frame, letterboxed.
///
/// Vision's face detector answers "is a face looking this way" — the one thing RTMPose
/// scores cannot, since they stay high for hidden ears and faces.
final class CalibrationFrameAnalyzer {
    struct Result {
        /// COCO-17 in pixel coordinates of the full, unmirrored frame.
        var keypoints: [PoseKeypoint]
        var face: CalibrationFace
        var imageSize: CGSize
        /// What RTMPose saw and where the user's face was, in top-left pixel coordinates (debug views).
        var crop: CGRect
        var faceBox: CGRect?
    }

    private let model: MLModel
    private let context: CIContext
    private let minConfidence: Double
    private let faceRequest: VNDetectFaceRectanglesRequest = {
        let request = VNDetectFaceRectanglesRequest()
        request.revision = VNDetectFaceRectanglesRequestRevision3
        return request
    }()

    /// Current crop in top-left pixel coordinates; nil = use the whole frame.
    private var crop: CGRect?

    private static let inputWidth = PoseCoordinateTransforms.rtmposeInputWidth
    private static let inputHeight = PoseCoordinateTransforms.rtmposeInputHeight
    private static let inputAspect = Double(inputWidth) / Double(inputHeight)

    init(model: MLModel, context: CIContext, minConfidence: Double) {
        self.model = model
        self.context = context
        self.minConfidence = minConfidence
    }

    func reset() {
        crop = nil
    }

    func analyze(_ image: CIImage) throws -> Result {
        let size = image.extent.size
        let rect = crop ?? Self.fitToInputAspect(CGRect(origin: .zero, size: size))
        let keypoints = try runPose(on: image, rect: rect)
        updateCrop(from: keypoints, imageSize: size)
        let (face, faceBox) = detectFace(in: image, keypoints: keypoints)
        return Result(keypoints: keypoints, face: face, imageSize: size, crop: rect, faceBox: faceBox)
    }

    // MARK: - RTMPose

    private func runPose(on image: CIImage, rect: CGRect) throws -> [PoseKeypoint] {
        let input = try PosePreprocess.makeRTMPoseInputArray()
        let pixels = try renderInput(image, rect: rect)
        try PosePreprocess.normalizeRGBAIntoRTMPoseInput(pixels, input: input,
                                                          width: Self.inputWidth, height: Self.inputHeight)
        let output = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: [
            "input_image": MLFeatureValue(multiArray: input)
        ]))
        guard let simccX = output.featureValue(for: "simcc_x")?.multiArrayValue,
              let simccY = output.featureValue(for: "simcc_y")?.multiArrayValue else {
            throw CalibrationFrameAnalyzerError.modelOutputMissing
        }
        let decoded = try SimCCDecoder.decodeToInputCoordinates(simccX: simccX, simccY: simccY)
        // Input pixel → frame pixel: the crop is 3:4 like the input, so one scale covers both axes.
        let scale = rect.width / Double(Self.inputWidth)
        let back = Affine2x3(a: scale, b: 0, c: rect.minX, d: 0, e: scale, f: rect.minY)
        return PoseCoordinateTransforms.applyInverseAffine(decoded: decoded, inverseAffine: back)
    }

    /// Renders `rect` (top-left pixel coordinates, may extend past the frame) into a 192×256
    /// RGBA buffer. Outside the frame is black, matching the zero border RTMPose was trained with.
    private func renderInput(_ image: CIImage, rect: CGRect) throws -> [UInt8] {
        let height = image.extent.height
        // Core Image is bottom-left based.
        let ciRect = CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        let scale = Double(Self.inputHeight) / rect.height
        let background = CIImage(color: .black).cropped(to: ciRect.union(image.extent))
        let scaled = image
            .composited(over: background)
            .transformed(by: CGAffineTransform(translationX: -ciRect.minX, y: -ciRect.minY))
            .applyingFilter("CILanczosScaleTransform", parameters: [
                kCIInputScaleKey: scale,
                kCIInputAspectRatioKey: 1.0,
            ])
        let target = CGRect(x: 0, y: 0, width: Self.inputWidth, height: Self.inputHeight)
        var pixels = [UInt8](repeating: 0, count: Self.inputWidth * Self.inputHeight * 4)
        pixels.withUnsafeMutableBytes { buffer in
            // Bitmap rows run top to bottom, as RTMPose expects.
            context.render(scaled, toBitmap: buffer.baseAddress!, rowBytes: Self.inputWidth * 4,
                           bounds: target, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        }
        return pixels
    }

    /// Follows the person with hysteresis: the crop only moves once they leave it or change
    /// size, so keypoint jitter does not feed back into the next crop.
    private func updateCrop(from keypoints: [PoseKeypoint], imageSize: CGSize) {
        let confident = keypoints.filter { $0.confidence >= minConfidence }
        let required = CocoJoint.required.allSatisfy { keypoints[$0.rawValue].confidence >= minConfidence }
        guard required, let bounds = Self.bounds(of: confident) else {
            crop = nil
            return
        }
        // Keypoints stop at the eyes and ankles; leave room for the head top and the soles.
        let person = bounds.insetBy(dx: 0, dy: -0.08 * bounds.height)
        let target = Self.fitToInputAspect(person.insetBy(dx: -0.125 * person.width, dy: -0.125 * person.height))
        if let current = crop, current.contains(person),
           current.height < 1.35 * target.height, current.height > 0.8 * target.height {
            return
        }
        crop = target
    }

    private static func bounds(of points: [PoseKeypoint]) -> CGRect? {
        guard let first = points.first else { return nil }
        var rect = CGRect(x: first.x, y: first.y, width: 0, height: 0)
        for point in points.dropFirst() {
            rect = rect.union(CGRect(x: point.x, y: point.y, width: 0, height: 0))
        }
        return rect.width > 1 && rect.height > 1 ? rect : nil
    }

    /// Grows `rect` around its centre to the RTMPose input aspect (3:4).
    static func fitToInputAspect(_ rect: CGRect) -> CGRect {
        var width = rect.width, height = rect.height
        if width / height > inputAspect {
            height = width / inputAspect
        } else {
            width = height * inputAspect
        }
        return CGRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
    }

    // MARK: - Face

    /// Looks for the user's face. Faces away from the head region (posters, bystanders) are ignored,
    /// otherwise a back view with a face in the background would never classify.
    private func detectFace(in image: CIImage, keypoints: [PoseKeypoint]) -> (CalibrationFace, CGRect?) {
        let ls = keypoints[CocoJoint.leftShoulder.rawValue], rs = keypoints[CocoJoint.rightShoulder.rawValue]
        let lh = keypoints[CocoJoint.leftHip.rawValue], rh = keypoints[CocoJoint.rightHip.rawValue]
        guard min(ls.confidence, rs.confidence, lh.confidence, rh.confidence) >= minConfidence else {
            return (.none, nil)
        }
        let shoulderY = (ls.y + rs.y) / 2
        let torso = (lh.y + rh.y) / 2 - shoulderY
        let headBox = CGRect(x: min(ls.x, rs.x) - 0.5 * torso, y: shoulderY - 1.0 * torso,
                             width: abs(ls.x - rs.x) + 1.0 * torso, height: 1.1 * torso)

        // Vision does not need 4K to find a face that is a tenth of the frame tall.
        let size = image.extent.size
        let downscale = min(1, 960 / size.height)
        let small = image.transformed(by: CGAffineTransform(scaleX: downscale, y: downscale))
        let handler = VNImageRequestHandler(ciImage: small, orientation: .up, options: [:])
        guard (try? handler.perform([faceRequest])) != nil, let faces = faceRequest.results else {
            return (.none, nil)
        }
        let match = faces
            .map { face -> (VNFaceObservation, CGPoint) in
                // Normalized, bottom-left origin → frame pixels, top-left origin.
                let box = face.boundingBox
                return (face, CGPoint(x: box.midX * size.width, y: (1 - box.midY) * size.height))
            }
            .filter { headBox.contains($0.1) }
            .max { $0.0.boundingBox.width < $1.0.boundingBox.width }
        guard let (face, _) = match else { return (.none, nil) }
        let box = face.boundingBox
        let pixels = CGRect(x: box.minX * size.width, y: (1 - box.maxY) * size.height,
                            width: box.width * size.width, height: box.height * size.height)
        return (CalibrationFace(isDetected: true, yawDeg: face.yaw.map { $0.doubleValue * 180 / .pi }), pixels)
    }
}

enum CalibrationFrameAnalyzerError: Error {
    case modelOutputMissing
}

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Diagnostics of one calibration run, in `Documents/calibration_diag/<sessionId>/` so a cancelled
/// run keeps them (the session folder itself is deleted):
/// - `debug_frames.csv`: everything the engine measured, per frame
/// - `camera.json`: camera, rotation and first-buffer facts, once
/// - `raw_<t>.jpg` / `analysis_<t>.jpg`: the buffer before and after levelling, 1/s for the first 10 s
///
/// On in debug builds, and in release when launched with `BPT_CALIB_DIAG=1`. The pictures show the
/// user's face: they stay on the phone until copied to the Mac's `~/bpt-data`.
final class CalibrationDebugLog {
    static let isEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return ProcessInfo.processInfo.environment["BPT_CALIB_DIAG"] == "1"
        #endif
    }()

    static func directory(sessionId: String) -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let url = documents.appendingPathComponent("calibration_diag", isDirectory: true)
            .appendingPathComponent(sessionId, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        return url
    }

    let directory: URL
    private var firstTimestamp: TimeInterval?
    private var lastImageSecond = -1
    private var wroteCamera = false

    private let queue = DispatchQueue(label: "com.bpt.calibration.debuglog")
    private var handle: FileHandle?  // queue only

    private static let header = [
        "timestamp", "guidance", "classified", "target", "holdProgress", "pass",
        "r", "delta", "faceDetected", "faceYaw", "rtmFace", "earL", "earR",
        "bodyH", "midX", "feet", "wristDropL", "wristDropR", "elbowRatioL", "elbowRatioR",
        "roll", "pitch", "meanConf", "bufferW", "bufferH", "residualDeg", "torso", "headTop",
    ].joined(separator: ",")

    init?(directory: URL) {
        guard Self.isEnabled else { return nil }
        self.directory = directory
        let url = directory.appendingPathComponent("debug_frames.csv")
        do {
            try Data((Self.header + "\n").utf8).write(to: url, options: .atomic)
            handle = try FileHandle(forWritingTo: url)
            try handle?.seekToEnd()
        } catch {
            return nil
        }
    }

    func append(timestamp: TimeInterval,
                output: CalibrationEngineOutput,
                r: Double?,
                delta: Double?,
                device: CalibrationDeviceState,
                face: CalibrationFace,
                bufferWidth: Int,
                bufferHeight: Int,
                residualDeg: Int) {
        let m = output.measurement
        let fields: [String] = [
            String(format: "%.3f", timestamp),
            "\"\(output.guidance.message)\"",
            output.classifiedView?.rawValue ?? "",
            output.targetView?.rawValue ?? "",
            String(format: "%.2f", output.holdProgress),
            output.isPassing ? "1" : "0",
            format(r), format(delta),
            face.isDetected ? "1" : "0", format(face.yawDeg),
            format(m?.face), format(m?.earLeft), format(m?.earRight),
            format(m?.bodyHeight), format(m?.midX), format(m?.feet),
            format(m?.leftWristDrop), format(m?.rightWristDrop),
            format(m?.leftElbowRatio), format(m?.rightElbowRatio),
            String(format: "%.2f", device.rollDeg), String(format: "%.2f", device.pitchDeg),
            format(m?.meanRequiredConfidence),
            String(bufferWidth), String(bufferHeight), String(residualDeg),
            format(m?.torso), format(m?.headTop),
        ]
        let line = Data((fields.joined(separator: ",") + "\n").utf8)
        queue.async { [self] in
            // A write after close is a no-op instead of an Objective-C exception.
            try? handle?.write(contentsOf: line)
        }
    }

    /// Once per run: camera and rotation facts. processingQueue only.
    func writeCameraOnce(_ info: @autoclosure () -> [String: Any]) {
        guard !wroteCamera else { return }
        wroteCamera = true
        guard let data = try? JSONSerialization.data(withJSONObject: info(), options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: directory.appendingPathComponent("camera.json"), options: .atomic)
    }

    /// The raw buffer and the levelled picture the engine judged, once a second for the first 10 s.
    /// processingQueue only.
    func saveImages(raw: CIImage, analysis: CIImage, timestamp: TimeInterval, context: CIContext) {
        let start = firstTimestamp ?? timestamp
        firstTimestamp = start
        let second = Int(timestamp - start)
        guard second < 10, second > lastImageSecond else { return }
        lastImageSecond = second
        let tag = String(format: "%.2f", timestamp - start)
        for (name, image) in [("raw", raw), ("analysis", analysis)] {
            let scale = min(1, 960 / max(image.extent.width, image.extent.height))
            let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cg = context.createCGImage(small, from: small.extent) else { continue }
            let url = directory.appendingPathComponent("\(name)_\(tag).jpg") as CFURL
            guard let destination = CGImageDestinationCreateWithURL(url, UTType.jpeg.identifier as CFString, 1, nil)
            else { continue }
            CGImageDestinationAddImage(destination, cg, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            CGImageDestinationFinalize(destination)
        }
    }

    func close() {
        queue.async { [self] in
            try? handle?.close()
            handle = nil
        }
    }

    private func format(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.4f", value)
    }
}

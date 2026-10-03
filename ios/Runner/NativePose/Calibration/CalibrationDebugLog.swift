import Foundation

/// Per-frame CSV of everything the engine measured, written into the session folder.
///
/// Only active in debug builds: the thresholds in `CalibrationConfig` are meant to be
/// tuned from these rows after a real-device run.
final class CalibrationDebugLog {
    static let isEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private let url: URL
    private let queue = DispatchQueue(label: "com.bpt.calibration.debuglog")
    private var handle: FileHandle?

    private static let header = [
        "timestamp", "guidance", "classified", "target", "holdProgress", "pass",
        "r", "delta", "face", "earL", "earR", "bodyH", "midX", "feet",
        "wristDropL", "wristDropR", "elbowRatioL", "elbowRatioR",
        "roll", "pitch", "meanConf",
    ].joined(separator: ",")

    init?(directory: URL) {
        guard Self.isEnabled else { return nil }
        url = directory.appendingPathComponent("debug_frames.csv")
        guard let data = (Self.header + "\n").data(using: .utf8) else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            handle = try FileHandle(forWritingTo: url)
            handle?.seekToEndOfFile()
        } catch {
            return nil
        }
    }

    func append(timestamp: TimeInterval,
                output: CalibrationEngineOutput,
                r: Double?,
                delta: Double?,
                device: CalibrationDeviceState) {
        guard let handle else { return }
        let m = output.measurement
        let fields: [String] = [
            String(format: "%.3f", timestamp),
            "\"\(output.guidance.message)\"",
            output.classifiedView?.rawValue ?? "",
            output.targetView?.rawValue ?? "",
            String(format: "%.2f", output.holdProgress),
            output.isPassing ? "1" : "0",
            format(r), format(delta),
            format(m?.face), format(m?.earLeft), format(m?.earRight),
            format(m?.bodyHeight), format(m?.midX), format(m?.feet),
            format(m?.leftWristDrop), format(m?.rightWristDrop),
            format(m?.leftElbowRatio), format(m?.rightElbowRatio),
            String(format: "%.2f", device.rollDeg), String(format: "%.2f", device.pitchDeg),
            format(m?.meanRequiredConfidence),
        ]
        let line = fields.joined(separator: ",") + "\n"
        queue.async {
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
        }
    }

    func close() {
        queue.async { [handle] in
            try? handle?.close()
        }
    }

    private func format(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        return String(format: "%.4f", value)
    }
}

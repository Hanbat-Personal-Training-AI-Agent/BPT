import Foundation
import UIKit

/// Writes one calibration session to disk: four JPEGs plus `manifest.json`.
///
///     Documents/calibration/<sessionId>/view_front.jpg ... manifest.json
///
/// The folder is what the SMPL fitting pipeline consumes; Info.plist enables file
/// sharing so it can be pulled off the device with Finder or the Files app.
final class CalibrationStore {
    struct Intrinsics {
        var fx: Double = 0
        var fy: Double = 0
        var cx: Double = 0
        var cy: Double = 0
        /// "attachment", "attachment_rotated" or "fov_estimate".
        var source: String = "fov_estimate"
    }

    struct ViewRecord {
        var label: CalibrationView
        var r: Double?
        var delta: Double?
        var earLeft: Double
        var earRight: Double
        var face: Double
        /// COCO-17 in unmirrored pixel coordinates of the saved image.
        var keypoints: [[Double]]
        var gravity: [Double]
        var timestamp: TimeInterval
    }

    let sessionId: String
    let directory: URL
    private let fileManager = FileManager.default
    private var records: [ViewRecord] = []

    init(sessionId: String = UUID().uuidString) throws {
        self.sessionId = sessionId
        let documents = try fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                            appropriateFor: nil, create: true)
        directory = documents.appendingPathComponent("calibration/\(sessionId)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func writeImage(_ image: UIImage, for view: CalibrationView, quality: Double) throws {
        guard let data = image.jpegData(compressionQuality: CGFloat(quality)) else {
            throw CalibrationStoreError.jpegEncodingFailed
        }
        try data.write(to: directory.appendingPathComponent(view.fileName), options: .atomic)
    }

    func add(_ record: ViewRecord) {
        records.removeAll { $0.label == record.label }
        records.append(record)
    }

    var capturedCount: Int { records.count }

    /// Writes `manifest.json` and returns its URL.
    @discardableResult
    func writeManifest(userHeightCm: Double,
                       imageWidth: Int,
                       imageHeight: Int,
                       intrinsics: Intrinsics,
                       reference: CalibrationReference?) throws -> URL {
        let formatter = ISO8601DateFormatter()
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "sessionId": sessionId,
            "createdAt": formatter.string(from: Date()),
            "deviceModel": Self.deviceModel(),
            "userHeightCm": userHeightCm,
            "imageWidth": imageWidth,
            "imageHeight": imageHeight,
            "intrinsics": [
                "fx": intrinsics.fx, "fy": intrinsics.fy,
                "cx": intrinsics.cx, "cy": intrinsics.cy,
                "source": intrinsics.source,
            ],
            "keypointFormat": "coco17_pixel_unmirrored",
            "yawConvention": "ccw_from_above_positive_user_turns_left; 0=facing_camera",
            "reference": [
                "ref_s": reference?.shoulderRatio ?? 0,
                "ref_h": reference?.hipRatio ?? 0,
                "o0": reference?.noseOffset ?? 0,
                "face_ref": reference?.face ?? 0,
            ],
            "views": records
                .sorted { orderIndex($0.label) < orderIndex($1.label) }
                .map { record in
                    [
                        "label": record.label.rawValue,
                        "file": record.label.fileName,
                        "nominalYawDeg": record.label.nominalYawDeg,
                        "r": record.r as Any,
                        "delta": record.delta as Any,
                        "earL": record.earLeft,
                        "earR": record.earRight,
                        "face": record.face,
                        "keypoints": record.keypoints,
                        "gravity": record.gravity,
                        "timestamp": record.timestamp,
                    ] as [String: Any]
                },
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest,
                                              options: [.prettyPrinted, .sortedKeys])
        let url = directory.appendingPathComponent("manifest.json")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Removes the whole session folder; used when the user cancels.
    func discard() {
        try? fileManager.removeItem(at: directory)
    }

    private func orderIndex(_ view: CalibrationView) -> Int {
        CalibrationView.allCases.firstIndex(of: view) ?? 0
    }

    private static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

enum CalibrationStoreError: Error {
    case jpegEncodingFailed
}

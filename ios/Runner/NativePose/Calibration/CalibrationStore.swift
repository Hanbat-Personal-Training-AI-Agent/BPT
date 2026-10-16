import Foundation

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

    /// All metadata bound to the image at selection time, not re-read at save time.
    struct Snapshot {
        let frame: CalibrationFrame
        let measurement: CalibrationMeasurement
        let imageWidth: Int
        let imageHeight: Int
        let intrinsics: Intrinsics
    }

    struct ViewRecord {
        let label: CalibrationView
        let snapshot: Snapshot
        let r: Double?
        let delta: Double?
    }

    let sessionId: String
    let directory: URL
    private let fileManager = FileManager.default
    private var records: [ViewRecord] = []
    private let writeData: (Data, URL) throws -> Void

    init(sessionId: String = UUID().uuidString,
         rootDirectory: URL? = nil,
         writeData: @escaping (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }) throws {
        guard sessionId.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else {
            throw CalibrationStoreError.invalidSessionID
        }
        self.sessionId = sessionId
        self.writeData = writeData
        let root = try rootDirectory ?? fileManager.url(for: .documentDirectory, in: .userDomainMask,
                                                        appropriateFor: nil, create: true)
            .appendingPathComponent("calibration", isDirectory: true)
        directory = root.appendingPathComponent(sessionId, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var capturedCount: Int { records.count }

    /// The manifest is the commit marker: it references only JPEGs successfully written.
    /// On manifest failure an unreferenced JPEG may remain; retry replaces that same view.
    /// Previously committed views and the in-memory count remain unchanged on any failure.
    func writeCapture(jpeg: Data, record: ViewRecord, userHeightCm: Double,
                      reference: CalibrationReference) throws {
        guard !jpeg.isEmpty else { throw CalibrationStoreError.jpegEncodingFailed }
        guard !records.contains(where: { $0.label == record.label }) else {
            throw CalibrationStoreError.duplicateView
        }
        let proposed = records + [record]
        let data = try manifestData(records: proposed, userHeightCm: userHeightCm, reference: reference)
        try writeData(jpeg, directory.appendingPathComponent(record.label.fileName))
        try writeData(data, directory.appendingPathComponent("manifest.json"))
        records = proposed
    }

    private func manifestData(records: [ViewRecord], userHeightCm: Double,
                              reference: CalibrationReference) throws -> Data {
        let formatter = ISO8601DateFormatter()
        // Keep schema-v1 top-level intrinsics as the front-view compatibility value.
        // New consumers use each view's intrinsics and dimensions.
        guard let front = records.first(where: { $0.label == .front })?.snapshot else {
            throw CalibrationStoreError.missingFrontView
        }
        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "isComplete": records.count == CalibrationView.allCases.count,
            "sessionId": sessionId,
            "createdAt": formatter.string(from: Date()),
            "deviceModel": Self.deviceModel(),
            "userHeightCm": userHeightCm,
            "imageWidth": front.imageWidth,
            "imageHeight": front.imageHeight,
            "intrinsics": intrinsicsDictionary(front.intrinsics),
            "perViewCameraMetadata": true,
            "keypointFormat": "coco17_pixel_unmirrored",
            "yawConvention": "ccw_from_above_positive_user_turns_left; 0=facing_camera",
            "reference": [
                "ref_s": reference.shoulderRatio,
                "ref_h": reference.hipRatio,
                "o0": reference.noseOffset,
                "face_ref": reference.face,
            ],
            "views": records
                .sorted { orderIndex($0.label) < orderIndex($1.label) }
                .map { record in
                    let snapshot = record.snapshot
                    let frame = snapshot.frame
                    let measurement = snapshot.measurement
                    return [
                        "label": record.label.rawValue,
                        "file": record.label.fileName,
                        "nominalYawDeg": record.label.nominalYawDeg,
                        "r": record.r.map { $0 as Any } ?? NSNull(),
                        "delta": record.delta.map { $0 as Any } ?? NSNull(),
                        "earL": measurement.earLeft,
                        "earR": measurement.earRight,
                        "face": measurement.face,
                        "keypoints": frame.keypoints.map {
                            [$0.x * Double(snapshot.imageWidth), $0.y * Double(snapshot.imageHeight), $0.score]
                        },
                        "gravity": frame.device.gravity,
                        "timestamp": frame.timestamp,
                        "deviceTimestamp": frame.device.timestamp.map { $0 as Any } ?? NSNull(),
                        "deviceMotionAvailable": frame.device.isAvailable,
                        "imageWidth": snapshot.imageWidth,
                        "imageHeight": snapshot.imageHeight,
                        "intrinsics": intrinsicsDictionary(snapshot.intrinsics),
                    ] as [String: Any]
                },
        ]
        return try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
    }

    private func intrinsicsDictionary(_ intrinsics: Intrinsics) -> [String: Any] {
        ["fx": intrinsics.fx, "fy": intrinsics.fy, "cx": intrinsics.cx, "cy": intrinsics.cy,
         "source": intrinsics.source]
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
    case invalidSessionID
    case duplicateView
    case missingFrontView
}

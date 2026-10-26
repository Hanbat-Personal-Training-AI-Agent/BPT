import XCTest
@testable import CalibrationEngineKit

/// Metadata-only replay harness; never reads RGB, labels, calibration targets, model output or GT coordinates.
final class PushUpSupportNumericReplayTests: XCTestCase {
    func testExistingPhoneLogsNumericReplay() throws {
        let env = ProcessInfo.processInfo.environment
        guard let directory = env["BPT_SUPPORT_NUMERIC_LOG_DIR"], let output = env["BPT_SUPPORT_NUMERIC_REPORT"] else {
            throw XCTSkip("Set numeric log directory and report destination to run the optional metadata replay")
        }
        var reports: [[String: Any]] = []
        for rotation in [0,90,270] { for camera in [1,2] {
            let name = "run_d26_xs_r\(rotation)_pushup_0003_cam\(camera).jsonl"
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath:url.path) else { continue }
            let lines = try String(contentsOf:url).split(separator:"\n").compactMap { line -> [String: Any]? in
                guard let data=line.data(using:.utf8) else { return nil }
                return (try? JSONSerialization.jsonObject(with:data)) as? [String:Any]
            }
            let fps = lines.first { $0["type"] as? String == "clip_start" }?["fps"] as? Double ?? .nan
            XCTAssertTrue(fps.isFinite && fps > 0)
            for assertion in [false,true] {
                var adapter=PushUpSupportEvidence2D(enabled:true), smoother=OverlaySmoother()
                var judged=0, inferred=0, hidden=0, expired=0, eligible=0, releases=0, resets=0
                var episodes: [String:Int] = [:], priorReason: [Int:String] = [:], maximumInferredAge = 0.0
                var corrected=0, correctionSum=0.0, maxCorrection=0.0, overlayCorrection=0.0
                var priorRaw:[Double]?, priorGuard:[Double]?, rawMaxStep=0.0, guardMaxStep=0.0
                for d in lines where d["type"] as? String == "judged" {
                    guard let flat=d["kp"] as? [Double], flat.count==51,
                          let size=d["size"] as? [Double], size.count==2,
                          let src=d["src"] as? Double, let arrival=d["arrival"] as? Double else { continue }
                    let k=(0..<17).map { PoseKeypoint(x:flat[3*$0],y:flat[3*$0+1],confidence:flat[3*$0+2]) }
                    let r=adapter.update(.init(keypoints:k,sourcePTS:src/fps,width:size[0],height:size[1],rotation:rotation,
                        epoch:"metadata_crop_identity_unrecorded", supportActive:assertion,
                        cameraEvidence:assertion ? .controlledReplayAssertion : .unknown,
                        sameHandRejected:d["same_hand"] as? Bool ?? false))
                    let smoothed=smoother.smooth(k,at:arrival), display=r.display(over:smoothed)
                    judged += 1; resets += r.reset ? 1 : 0
                    for (index,w) in [(9,r.corridor.left),(10,r.corridor.right)] {
                        if priorReason[index] != w.reason.rawValue { episodes[w.reason.rawValue,default:0] += 1 }
                        priorReason[index]=w.reason.rawValue
                        if w.inferred { maximumInferredAge=max(maximumInferredAge,w.occlusionAge ?? 0) }
                        inferred += w.inferred ? 1 : 0; hidden += w.displayPoint == nil ? 1 : 0
                        expired += w.reason == .occlusionExpired ? 1 : 0
                        releases += w.reason == .observedReleased ? 1 : 0
                        if w.assessmentEligible {
                            eligible += 1
                            XCTAssertEqual(w.displayPoint?.x,k[index].x); XCTAssertEqual(w.displayPoint?.y,k[index].y)
                        }
                        XCTAssertFalse(w.inferred && w.armAndHandCoachingEligible)
                        if let c=w.correctionMagnitude, c>0 { corrected += 1; correctionSum += c; maxCorrection=max(maxCorrection,c) }
                        overlayCorrection += hypot(smoothed[index].x-k[index].x,smoothed[index].y-k[index].y)
                    }
                    let raw=[k[9].x,k[9].y,k[10].x,k[10].y]
                    if let old=priorRaw { for i in [0,2] { rawMaxStep=max(rawMaxStep,hypot(raw[i]-old[i],raw[i+1]-old[i+1])) } }
                    let guarded=[display[9].x,display[9].y,display[10].x,display[10].y]
                    if let old=priorGuard, !r.corridor.withholdSkeleton {
                        for i in [0,2] { guardMaxStep=max(guardMaxStep,hypot(guarded[i]-old[i],guarded[i+1]-old[i+1])) }
                    }
                    priorRaw=raw; priorGuard=r.corridor.withholdSkeleton ? nil : guarded
                }
                reports.append(["log":name,"variant":assertion ? "asserted_fixed_camera_and_support_harness_only" : "available_evidence_unknown_camera_contact",
                    "judged":judged,"wrist_samples":judged*2,"inferred":inferred,"hidden":hidden,"expired":expired,
                    "reason_episodes":episodes,"maximum_inferred_age_s":maximumInferredAge,"eligible_unchanged":eligible,"released":releases,"resets":resets,"corrected":corrected,
                    "correction_sum_px":correctionSum,"correction_max_px":maxCorrection,
                    "reconstructed_overlay_mean_correction_px":overlayCorrection/Double(max(1,judged*2)),
                    "raw_max_step_px":rawMaxStep,"guard_max_visible_step_px":guardMaxStep])
            }
        } }
        XCTAssertFalse(reports.isEmpty)
        let report:[String:Any] = ["reports":reports,
            "limitations":["No RGB or GT labels; no accuracy claim", "Assertion applies to entire clip as harness scope, not detected contact or visibility",
                "Replay reads src/fps source time; no wrist coordinates from GT", "Crop/tracker IDs absent; held constant in harness, unlike conservative native crop resets",
                "Current overlay reconstructed from judged raw keypoints and arrival time; actual accepted MediaPipe inputs/ungathered display frames unavailable",
                "Available-evidence variant has no trustworthy camera/contact evidence and cannot acquire support"]]
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys])
        try data.write(to:URL(fileURLWithPath:output))
    }
}

import XCTest
@testable import CalibrationEngineKit

/// Synthetic source-contract witnesses, never media/accuracy data. All thresholds remain native defaults;
/// one-rep baseline/trend windows and disabled-by-default foot/shrug rules are explicitly enabled for tests.
final class FormFaultCoverageFixtureTests: XCTestCase {
    private func point(_ x: Double, _ y: Double) -> PoseKeypoint { .init(x:x,y:y,confidence:0.95) }
    private func sidePose(shoulder: (Double,Double), hip: (Double,Double), knee: (Double,Double),
                          ankle: (Double,Double), elbow: (Double,Double), wrist: (Double,Double),
                          earOffset: (Double,Double)) -> [PoseKeypoint] {
        var p = [PoseKeypoint](repeating:point(0,0),count:17)
        for (index,xy) in [(3,(shoulder.0+earOffset.0,shoulder.1+earOffset.1)),(5,shoulder),(7,elbow),
                           (9,wrist),(11,hip),(13,knee),(15,ankle)] {
            p[index] = point(xy.0,xy.1); p[index+1] = point(xy.0,xy.1)
        }
        p[0] = point(p[3].x+20,p[3].y)
        return p
    }
    private func pushup(_ rep: Int, _ step: Int) -> [PoseKeypoint] {
        let drop = [0.0,60,-60,0,0][step]
        let head = [0.0,120,-120,0,0][step]
        var elbow = (300.0,250.0), wrist = (350.0,300.0)
        if rep == 0 {
            if step == 2 { elbow = (250,225); wrist = (300,300) }
            else { elbow = (340,250); wrist = (380,300) }
        } else if rep == 1 && step != 2 { wrist = (300,300) }
        return sidePose(shoulder:(300,200),hip:(150,200+drop),knee:(75,200),ankle:(0,200),
                        elbow:elbow,wrist:wrist,earOffset:(30,-20+head))
    }
    private func squat(_ rep: Int, _ step: Int) -> [PoseKeypoint] {
        let hipY = [250.0,275,300,250,250][step]
        let shoulderY = [100.0,125,150,150,150][step]
        let shoulderX = 200.0 + (rep == 0 ? 0 : 70) + (step >= 3 ? 70 : 0)
        let kneeX = step == 2 ? (rep == 0 ? 300.0 : 230) : (rep == 0 ? 200.0 : 230)
        return sidePose(shoulder:(shoulderX,shoulderY),hip:(200,hipY),knee:(kneeX,350),ankle:(200,400),
                        elbow:(shoulderX+20,shoulderY+40),wrist:(shoulderX+40,shoulderY+80),earOffset:(20,-30))
    }
    private func frontalSquat(_ rep: Int, _ step: Int) -> [PoseKeypoint] {
        var p = squat(rep,step)
        p[5] = point(140,100); p[6] = point(260,100)
        let hipY = [240.0,270,300,270,240][step]
        p[11] = point(180,hipY); p[12] = point(220,hipY)
        p[13] = point(195,350); p[14] = point(205,350)
        p[15] = point(150,400); p[16] = point(250,400)
        p[3] = point(190,70); p[4] = point(210,70); p[0] = point(215,70)
        return p
    }
    private func rowPose(_ rep: Int, _ step: Int) -> [PoseKeypoint] {
        let shoulder: (Double,Double) = rep == 0 ? (300,200) : (step == 3 ? (350,250) : (200,100))
        let elbow: (Double,Double) = rep == 0 ? (200,150) : (shoulder.0+20,shoulder.1+40)
        let headOffset: (Double,Double) = step == 1 ? (5,-5) : (step == 2 ? (30,-140) : (30,-20))
        return sidePose(shoulder:shoulder,hip:(150,300),knee:(120,370),ankle:(100,450),
                        elbow:elbow,wrist:(elbow.0+20,elbow.1+60),earOffset:headOffset)
    }
    private func feet(_ step: Int) -> FootKeypoints {
        let toe = point(200,400), heel = point(200,step == 0 ? 410 : 390)
        return .init(leftBigToe:toe,rightBigToe:toe,leftSmallToe:toe,rightSmallToe:toe,leftHeel:heel,rightHeel:heel)
    }
    private func emit(_ name: String, exercise: FormExercise, pose: (Int,Int) -> [PoseKeypoint],
                      feet useFeet: Bool = false) throws -> [[String:Any]] {
        var records = [[String:Any]]()
        let tracker = FormWarningTracker(exercise:exercise)
        tracker.common.baselineRepCount = 1; tracker.common.trendRepCount = 1
        tracker.squat.heelRiseEnabled = true; tracker.row.shrugEnabled = true
        let run = "coverage-v2-\(name)"
        let sources = (0..<20).map { FormFaultSource(frame:$0,sourceIndex:$0,timeValue:Int64($0),timeScale:50,
            session:run,kind:"synthetic_source_contract",flush:false) }
        let writer = FormFaultEvidence(runID:run,binding:["fixture":"synthetic_actual_tracker_coverage_v2",
            "accuracyClaim":false,"thresholdPolicy":"native_defaults", "baselineRepCount":1,"trendRepCount":1,
            "enabledTestRules":["squat_heel_rise","row_shrug"]],expectedSources:sources) { records.append($0) }
        tracker.faultEvidence = writer
        for rep in 0..<4 {
            for step in 0..<5 {
                let frame = rep*5+step
                tracker.faultSource = sources[frame]
                tracker.observe(frameIndex:frame,coco17:pose(rep,step),feet:useFeet ? feet(step) : nil,
                                phase:["top","descending","bottom","ascending","top"][step])
                if step == 0 { tracker.beginRep() } else { tracker.recordCurrentFrame() }
            }
            tracker.finishRep(repIndex:rep+1)
        }
        writer.finish(reason:"synthetic_fixture_drained",sourceDrained:true)
        XCTAssertEqual(records.last?["sourceCoverageComplete"] as? Bool,true)
        if let directory = ProcessInfo.processInfo.environment["BPT_FAULT_COVERAGE_FIXTURE_DIR"] {
            let url = URL(fileURLWithPath:directory).appendingPathComponent("native-fault-actual-fixture-coverage-v2-\(name).jsonl")
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            var data = Data()
            for record in records { data += try JSONSerialization.data(withJSONObject:record,options:.sortedKeys); data.append(10) }
            try data.write(to:url,options:.withoutOverwriting)
        }
        return records
    }
    func testAllTwentyRulesHaveActualSupportedPositiveWitnesses() throws {
        let cases: [(String,FormExercise,(Int,Int)->[PoseKeypoint],Bool)] = [
            ("pushup-side",.pushUp,pushup,false),("squat-side",.squat,squat,true),
            ("squat-front",.squat,frontalSquat,true),("row-side",.barbellRow,rowPose,false)]
        var positives = Set<String>()
        var details = [String:[String]]()
        for (name,exercise,pose,useFeet) in cases {
            let records = try emit(name,exercise:exercise,pose:pose,feet:useFeet)
            for rep in records.filter({ $0["type"] as? String == "rep" }) {
                let judgment = (rep["judgements"] as! [String:Any])["2d"] as! [String:Any]
                for rule in judgment["rules"] as! [[String:Any]] {
                    if rule["rawFired"] as? Bool == true && rule["positiveOperandEvidence"] as? Bool == true {
                        let key = rule["rule"] as! String; positives.insert(key); details[name,default:[]].append(key)
                    }
                }
            }
        }
        let expected = Set([FormExercise.pushUp,.squat,.barbellRow].flatMap { exercise in
            (FormWarningTracker.rules[exercise] ?? []).map(\.key).filter { !$0.hasPrefix("setup_") }
        })
        XCTAssertEqual(positives,expected,"Missing: \(expected.subtracting(positives).sorted()); actual per case: \(details)")
    }
}

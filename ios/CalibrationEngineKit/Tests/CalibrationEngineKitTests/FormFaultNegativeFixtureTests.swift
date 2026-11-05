import XCTest
@testable import CalibrationEngineKit

/// Fully observed neutral source-contract fixtures. These are not normal-person or clinical labels.
final class FormFaultNegativeFixtureTests: XCTestCase {
    private func point(_ x: Double, _ y: Double) -> PoseKeypoint { .init(x:x,y:y,confidence:0.95) }
    private func paired(_ values: [(Int,Double,Double)]) -> [PoseKeypoint] {
        var p = [PoseKeypoint](repeating:point(0,0),count:17)
        for (i,x,y) in values { p[i]=point(x,y); if i != 0 { p[i+1]=point(x,y) } }
        return p
    }
    private func pushup(_ step: Int) -> [PoseKeypoint] {
        paired([(0,350,180),(3,330,180),(5,300,200),(7,300,250),(9,300,300),
                (11,150,200),(13,75,200),(15,0,200)])
    }
    private func row(_ step: Int) -> [PoseKeypoint] {
        paired([(0,350,180),(3,330,180),(5,300,200),(7,200,150),(9,220,210),
                (11,150,300),(13,120,370),(15,100,450)])
    }
    private func sideSquat(_ step: Int) -> [PoseKeypoint] {
        // Only knee flexion changes; torso/hip/shoulder heights remain equal across the selected ascent window.
        paired([(0,270,70),(3,250,70),(5,250,100),(7,270,140),(9,290,180),
                (11,200,250),(13,step == 2 ? 230 : 200,350),(15,200,400)])
    }
    private func frontSquat(_ step: Int) -> [PoseKeypoint] {
        var p=sideSquat(step)
        p[5]=point(140,100);p[6]=point(260,100)
        let hipY=[240.0,270,300,270,240][step]
        p[11]=point(180,hipY);p[12]=point(220,hipY)
        p[13]=point(140,350);p[14]=point(260,350) // ratio 120/100 > default 1.0
        p[15]=point(150,400);p[16]=point(250,400)
        p[3]=point(190,70);p[4]=point(210,70);p[0]=point(215,70)
        return p
    }
    private func feet() -> FootKeypoints {
        let toe=point(200,400),heel=point(200,400) // no heel/toe displacement, regardless of changing shin length
        return .init(leftBigToe:toe,rightBigToe:toe,leftSmallToe:toe,rightSmallToe:toe,leftHeel:heel,rightHeel:heel)
    }
    private func emit(_ name: String, exercise: FormExercise, pose: (Int)->[PoseKeypoint],
                      feet useFeet: Bool) throws -> [[String:Any]] {
        var records=[[String:Any]]()
        let tracker=FormWarningTracker(exercise:exercise)
        tracker.common.baselineRepCount=1;tracker.common.trendRepCount=1
        tracker.squat.heelRiseEnabled=true;tracker.row.shrugEnabled=true
        let run="negative-v1-\(name)"
        let sources=(0..<20).map { FormFaultSource(frame:$0,sourceIndex:$0,timeValue:Int64($0),timeScale:50,
            session:run,kind:"synthetic_source_contract",flush:false) }
        let writer=FormFaultEvidence(runID:run,binding:["fixture":"synthetic_actual_tracker_negative_v1",
            "accuracyClaim":false,"thresholdPolicy":"native_defaults","baselineRepCount":1,"trendRepCount":1,
            "enabledTestRules":["squat_heel_rise","row_shrug"]],expectedSources:sources) { records.append($0) }
        tracker.faultEvidence=writer
        for rep in 0..<4 {
            for step in 0..<5 {
                let frame=rep*5+step
                tracker.faultSource=sources[frame]
                tracker.observe(frameIndex:frame,coco17:pose(step),feet:useFeet ? feet() : nil,
                    phase:["top","descending","bottom","ascending","top"][step])
                if step == 0 { tracker.beginRep() } else { tracker.recordCurrentFrame() }
            }
            tracker.finishRep(repIndex:rep+1)
        }
        writer.finish(reason:"synthetic_fixture_drained",sourceDrained:true)
        XCTAssertEqual(records.last?["sourceCoverageComplete"] as? Bool,true)
        if let directory=ProcessInfo.processInfo.environment["BPT_FAULT_NEGATIVE_FIXTURE_DIR"] {
            let url=URL(fileURLWithPath:directory).appendingPathComponent("native-fault-actual-fixture-negative-v1-\(name).jsonl")
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
            var data=Data()
            for record in records { data += try JSONSerialization.data(withJSONObject:record,options:.sortedKeys);data.append(10) }
            try data.write(to:url,options:.withoutOverwriting)
        }
        return records
    }
    func testAllTwentyRulesHaveActualSupportedNegativeWitnesses() throws {
        let cases:[(String,FormExercise,(Int)->[PoseKeypoint],Bool)]=[
            ("pushup-side",.pushUp,pushup,false),("squat-side",.squat,sideSquat,true),
            ("squat-front",.squat,frontSquat,true),("row-side",.barbellRow,row,false)]
        var negatives=Set<String>()
        for (name,exercise,pose,useFeet) in cases {
            for rep in try emit(name,exercise:exercise,pose:pose,feet:useFeet).filter({ $0["type"] as? String == "rep" }) {
                let judgement=(rep["judgements"] as! [String:Any])["2d"] as! [String:Any]
                for rule in judgement["rules"] as! [[String:Any]] {
                    if rule["callState"] as? String == "false",rule["rawFired"] as? Bool == false,
                       rule["negativeOperandEvidence"] as? Bool == true { negatives.insert(rule["rule"] as! String) }
                }
            }
        }
        let expected=Set([FormExercise.pushUp,.squat,.barbellRow].flatMap {
            (FormWarningTracker.rules[$0] ?? []).map(\.key).filter { !$0.hasPrefix("setup_") }
        })
        XCTAssertEqual(negatives,expected,"Missing negative witnesses: \(expected.subtracting(negatives).sorted())")
    }
}

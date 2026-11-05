import Foundation
import XCTest
import simd
@testable import CalibrationEngineKit

final class CoachingCandidateTests: XCTestCase {
    func config(_ variant:String,_ values:[String:Any]=[:]) throws -> CoachingCandidateEngine.Configuration {
        var overrides:[String:Any] = ["support.maximumHipRatioCorrection":0.05,"row.kneeExtensionLower":10,"row.elbowFlexionLower":10]
        overrides.merge(values,uniquingKeysWith:{$1})
        return try .init(experimentID:"synthetic-engineering-only",source:"synthetic configured candidate; not expert targets",experimentDeclaredAt:"synthetic-test-declaration-2026-11-02",variant:variant,overrides:overrides,provenance:Dictionary(uniqueKeysWithValues:overrides.keys.map {($0,"synthetic engineering test value")}))
    }
    func frame(_ index:Int,_ phase:String,_ exercise:String="squat",torso:Double=0,hipY:Double=500,shoulderY:Double=300,knee:Double=110,elbow:Double=150,sag:Double?=nil,invalid:[Int]=[],score:[Int:Double]=[:],capture:String="synthetic-capture",flush:Bool=false) -> CoachingCandidateEngine.Frame {
        var p=[SIMD3<Double>](repeating:.zero,count:17)
        let rad=torso*Double.pi/180
        p[0]=SIMD3(0,0,0);p[8]=SIMD3(0,-cos(rad),-sin(rad));p[1]=SIMD3(-0.2,0,0);p[4]=SIMD3(0.2,0,0)
        for (s,h,k,a,sh,e,w) in [(1,1,2,3,14,15,16),(-1,4,5,6,11,12,13)] {
            let x = -Double(s)*0.2;p[h]=SIMD3(x,0,0);p[k]=SIMD3(x,0.5,0)
            let kr=knee*Double.pi/180;p[a]=p[k]+SIMD3(0,-cos(kr)*0.5,sin(kr)*0.5)
            p[sh]=SIMD3(-Double(s)*0.3,-1,0);p[e]=SIMD3(-Double(s)*0.3,-0.5,0)
            let er=elbow*Double.pi/180;p[w]=p[e]+SIMD3(0,-cos(er)*0.5,sin(er)*0.5)
        }
        if let sag {
            p[8]=SIMD3(0,0,0);p[0]=SIMD3(0,sag,1);p[3]=SIMD3(-0.2,0,2);p[6]=SIMD3(0.2,0,2)
        }
        var points=[SIMD3<Double>](repeating:SIMD3(100,100,1),count:17)
        for (sh,h) in [(5,11),(6,12)] { points[sh]=SIMD3(100,shoulderY,1);points[h]=SIMD3(100,hipY,1) }
        var confidence=[Double](repeating:1,count:17);for (i,v) in score {confidence[i]=v}
        return .init(source:["frame":index,"source_index":index,"source_pts":Double(index)*0.1,"source_time_value":index,"source_time_scale":10,"epoch":1,"time_basis":"sample_pts_seconds"],context:["exercise":exercise,"phase":phase,"side":"left","side_view":NSNull(),"source_kind":"video_frame","flush_tail":flush,"rotation":0,"size":[640,480],"source_mirrored":false],raw3D:p,assessment3D:p,raw2D:points,confidence:confidence,invalid:Set(invalid),state:"ok",captureID:capture)
    }
    func rule(_ output:[String:Any],_ name:String)->[String:Any] { (output["rules"] as! [[String:Any]]).first { ($0["id"] as! String).contains(name) }! }
    func testPushupScopedDeviationNegativeAndOcclusion() throws {
        var engine=CoachingCandidateEngine();let config=try config("floor")
        XCTAssertEqual(rule(try engine.update(frame(0,"descending","pushup",sag:0.5),configuration:config),"camera_body_line")["state"] as? String,"positive_evidence")
        XCTAssertEqual(rule(try engine.update(frame(1,"descending","pushup",sag:0.1),configuration:config),"camera_body_line")["state"] as? String,"negative_evidence")
        XCTAssertEqual(rule(try engine.update(frame(2,"descending","pushup",sag:0.5,invalid:[3]),configuration:config),"camera_body_line")["state"] as? String,"unknown")
        let current=try engine.update(frame(3,"descending","pushup",sag:0.5),configuration:config,includeRequests:true)
        let request=(current["requests"] as! [[String:Any]])[0]
        let observed=(request["observations"] as! [String:[String:Any]]).values.first!
        XCTAssertNil((observed["scope"] as! [String:Any])["modelSha256"])
        XCTAssertFalse(((rule(current,"camera_body_line")["components"] as! [[String:Any]])[0]["reasons"] as! [String]).contains("complete_source_identity_required"))
    }
    func testSquatANDUsesSameSourcePrefixAndPreservesKnownPositive() throws {
        var engine=CoachingCandidateEngine();let config=try config("bodyweight")
        _=try engine.update(frame(0,"descending"),configuration:config)
        _=try engine.update(frame(1,"bottom"),configuration:config)
        let good=rule(try engine.update(frame(2,"ascending",torso:15,hipY:470,shoulderY:295),configuration:config),"early_ascent")
        XCTAssertEqual(good["state"] as? String,"positive_evidence")
        var missing=frame(3,"ascending",torso:20,hipY:460,shoulderY:290)
        missing = .init(source:missing.source,context:missing.context,raw3D:missing.raw3D,assessment3D:missing.assessment3D,raw2D:nil,confidence:missing.confidence,invalid:missing.invalid,state:missing.state,captureID:missing.captureID)
        let withheld=rule(try engine.update(missing,configuration:config),"early_ascent")
        XCTAssertEqual(withheld["state"] as? String,"unknown")
        XCTAssertEqual((withheld["components"] as! [[String:Any]])[0]["state"] as? String,"positive_evidence")
        XCTAssertEqual(rule(try engine.update(frame(5,"ascending",torso:30),configuration:config),"early_ascent")["state"] as? String,"unknown")
    }
    func testRowMotionFourComponentsAndSourceReset() throws {
        var engine=CoachingCandidateEngine();let config=try config("strict_bent_over")
        _=try engine.update(frame(0,"lowering","barbell-row"),configuration:config)
        _=try engine.update(frame(1,"pulling","barbell-row"),configuration:config)
        let good=rule(try engine.update(frame(2,"pulling","barbell-row",knee:140,elbow:110),configuration:config),"phase_prefix_leg")
        XCTAssertEqual(good["state"] as? String,"positive_evidence")
        let partial=rule(try engine.update(frame(3,"pulling","barbell-row",knee:145,elbow:105,invalid:[16]),configuration:config),"phase_prefix_leg")
        XCTAssertEqual(partial["state"] as? String,"unknown")
        XCTAssertEqual((partial["components"] as! [[String:Any]]).filter { $0["state"] as? String == "positive_evidence" }.count,3)
        XCTAssertEqual(rule(try engine.update(frame(4,"pulling","barbell-row",knee:150,elbow:100,capture:"other"),configuration:config),"phase_prefix_leg")["state"] as? String,"unknown")
    }
    func testRollingWindowIncompleteVersusPositiveNegativeAndFlush() throws {
        let config=try config("strict_bent_over",["window.rowRangeSeconds":0.2])
        for (angles,expected) in [([0.0,10,50],"positive_evidence"),([0.0,1,2],"negative_evidence")] {
            var engine=CoachingCandidateEngine()
            XCTAssertEqual(rule(try engine.update(frame(0,"pulling","barbell-row",torso:angles[0]),configuration:config),"torso_window")["state"] as? String,"unknown")
            _=try engine.update(frame(1,"lowering","barbell-row",torso:angles[1]),configuration:config)
            XCTAssertEqual(rule(try engine.update(frame(2,"pulling","barbell-row",torso:angles[2]),configuration:config),"torso_window")["state"] as? String,expected)
            XCTAssertEqual(rule(try engine.update(frame(3,"pulling","barbell-row",torso:80,flush:true),configuration:config),"torso_window")["state"] as? String,"unknown")
        }
    }
    func testUnconfiguredTargetsAndExplicitVariantNeverAutoApprove() throws {
        var engine=CoachingCandidateEngine();let config=try config("bodyweight")
        let output=try engine.update(frame(0,"top"),configuration:config)
        let target=rule(output,"top_extension")
        XCTAssertEqual(target["state"] as? String,"unknown");XCTAssertEqual(target["configured"] as? Bool,false)
        let configured=try self.config("bodyweight",["squat.topKneeLower":100,"squat.topHipLower":0])
        XCTAssertEqual(rule(try engine.update(frame(1,"top"),configuration:configured),"top_extension")["state"] as? String,"positive_evidence")
        XCTAssertEqual(output["delivered"] as? Bool,false)
        XCTAssertThrowsError(try CoachingCandidateEngine.Configuration(experimentID:"x",source:"x",experimentDeclaredAt:"synthetic",variant:"bodyweight",overrides:["squat.topKneeLower":160]))
    }
    func testBottomToPullingAndSeparatedChangesAreOnlyPrefixCooccurrence() throws {
        var engine=CoachingCandidateEngine();let config=try config("strict_bent_over")
        _=try engine.update(frame(0,"bottom","barbell-row"),configuration:config)
        _=try engine.update(frame(1,"pulling","barbell-row"),configuration:config)
        _=try engine.update(frame(2,"pulling","barbell-row",knee:140,elbow:150),configuration:config)
        let result=rule(try engine.update(frame(3,"pulling","barbell-row",knee:140,elbow:110),configuration:config),"phase_prefix_leg")
        XCTAssertEqual(result["state"] as? String,"positive_evidence")
        XCTAssertTrue((result["target"] as! String).contains("not instantaneous coincidence"))
    }
    func testCircularTorsoAgreementAndFixedDerivedBound() throws {
        var engine=CoachingCandidateEngine();let config=try config("strict_bent_over",["window.rowRangeSeconds":0.2])
        for i in 0...2 {
            let raw=frame(i,"pulling","barbell-row",torso:179),ass=frame(i,"pulling","barbell-row",torso:-179)
            let input=CoachingCandidateEngine.Frame(source:raw.source,context:raw.context,raw3D:raw.raw3D,assessment3D:ass.assessment3D,raw2D:raw.raw2D,confidence:raw.confidence,invalid:raw.invalid,state:raw.state,captureID:raw.captureID)
            let output=try engine.update(input,configuration:config,includeRequests:true)
            if i==2 {
                XCTAssertEqual(rule(output,"torso_window")["state"] as? String,"negative_evidence")
                let request=(output["requests"] as! [[String:Any]]).first {($0["criterion"] as! [String:Any])["id"] as? String == "row.camera_torso_window_transfer"}!
                let observation=(request["observations"] as! [String:[String:Any]]).values.first!
                XCTAssertEqual((observation["support"] as! [String:Any])["maximumCorrectionDifference"] as? Double,20)
            }
        }
    }
    func testRuntimeOffAndOwnedNamespaceValidation() throws {
        XCTAssertNil(try CoachingCandidateRuntime.configuration(environment:[:]))
        XCTAssertNil(try CoachingCandidateRuntime.configuration(environment:["BPT_EXPERIMENTAL_COACHING":"1"]))
        XCTAssertThrowsError(try CoachingCandidateRuntime.configuration(environment:["BPT_EXPERIMENTAL_COACHING":"1","BPT_EXPERIMENTAL_CRITERIA_CANDIDATE":"1"]))
        XCTAssertEqual(try CoachingCandidateRuntime.namespace(environment:["BPT_EXPERIMENTAL_CRITERIA_CANDIDATE":"1","BPT_TERMINAL_NAMESPACE":"coaching-candidate-owned-1"]),"coaching-candidate-owned-1")
        XCTAssertThrowsError(try CoachingCandidateRuntime.namespace(environment:["BPT_EXPERIMENTAL_CRITERIA_CANDIDATE":"1","BPT_TERMINAL_NAMESPACE":"../video_runs"]))
    }

    func testNativeSyntheticProposalAndUnknownExpiryUseIndependentSource() throws {
        var fixture=CoachingCandidateSelfTest()
        let proposal=try XCTUnwrap(fixture.run(stage:"positive",declaredAt:"synthetic-test"))
        XCTAssertEqual(proposal["schema"] as? String,"bpt.coaching-candidate-proposal.v1")
        XCTAssertEqual(proposal["predicateMeaning"] as? String,"deviation")
        XCTAssertEqual((proposal["context"] as! [String:Any])["source_kind"] as? String,"synthetic_fixture")
        let clear=try XCTUnwrap(fixture.run(stage:"occluded",declaredAt:"synthetic-test"))
        XCTAssertEqual(clear["schema"] as? String,"bpt.coaching-candidate-clear.v1")
        XCTAssertEqual(clear["previousProposalId"] as? String,proposal["proposalId"] as? String)
        XCTAssertEqual(clear["captureId"] as? String,proposal["captureId"] as? String)
    }
    func testDesiredMatchPositiveNeverBecomesFaultProposal() throws {
        var engine=CoachingCandidateEngine(),presenter=CoachingCandidateProposal()
        let config=try config("bodyweight",["squat.topKneeLower":100,"squat.topHipLower":0])
        let output=try engine.update(frame(0,"top"),configuration:config)
        XCTAssertEqual(rule(output,"top_extension")["state"] as? String,"positive_evidence")
        XCTAssertNil(presenter.next(output))
    }

    func testOneMissingJointScoreDoesNotEraseSupportedOtherArm() throws {
        let original=frame(0,"top","pushup")
        func flat(_ p:[SIMD3<Double>]?)->Any {p!.flatMap {[$0.x,$0.y,$0.z]}}
        var scores:[Any]=[Double](repeating:1,count:17);scores[16]=NSNull()
        var row=original.source;row.merge(original.context,uniquingKeysWith:{$1})
        row.merge(["raw_3d":flat(original.raw3D),"assessment_3d":flat(original.assessment3D),"raw_2d":flat(original.raw2D),"confidence_h36m":scores,"invalid":[],"assessment_state":"ok"],uniquingKeysWith:{$1})
        let decoded=CoachingCandidateEngine.Frame.terminal(row,exercise:"pushup",captureID:"synthetic-null-score")
        var engine=CoachingCandidateEngine()
        let output=try engine.update(decoded,configuration:config("floor",["pushup.topElbowLower":100]))
        let components=rule(output,"top_extension")["components"] as! [[String:Any]]
        XCTAssertEqual(components[0]["state"] as? String,"positive_evidence")
        XCTAssertEqual(components[1]["state"] as? String,"unknown")
    }

    func testLiveProcessorPreservesSourceRawAndOfflineResultsWithoutLogger() throws {
        var live = CoachingCandidateRuntime.Processor(), offline = CoachingCandidateEngine()
        let configuration = try config("floor")
        for i in 0..<6 {
            let original = frame(i, "descending", "pushup", sag: i == 3 ? 0.1 : 0.5)
            let input = CoachingCandidateEngine.Frame.live(source: original.source, context: original.context,
                raw3D: original.raw3D, assessment3D: original.assessment3D, raw2D: original.raw2D,
                confidence: original.confidence, invalid: original.invalid, state: original.state, captureID: original.captureID)
            let expected = try offline.update(original, configuration: configuration, includeRequests: true)
            let result = live.process(input, configuration: .success(configuration), includeRequests: true)
            XCTAssertNil(result.error)
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: XCTUnwrap(result.candidate), options: [.sortedKeys]),
                           try JSONSerialization.data(withJSONObject: expected, options: [.sortedKeys]))
            XCTAssertEqual(input.raw3D, original.raw3D)
            XCTAssertEqual((result.candidate?["source"] as? NSDictionary), original.source as NSDictionary)
        }
    }

    func testLiveProcessorUnknownPhaseSideMalformedAndSourceChangesClearOldIdentity() throws {
        let configuration = try config("floor")
        for change in ["capture", "epoch", "rotation", "side", "phase", "source_kind", "malformed", "nil"] {
            var runtime = CoachingCandidateRuntime.Processor()
            let first = frame(0, "descending", "pushup", sag: 0.5)
            let proposal = try XCTUnwrap(runtime.process(first, configuration: .success(configuration)).proposal)
            var source = first.source, context = first.context
            source["source_index"] = 1; source["source_pts"] = 0.1
            if change == "epoch" { source["epoch"] = 2 }
            if change == "rotation" { context["rotation"] = 90 }
            if change == "source_kind" { context["source_kind"] = "camera_capture_index" }
            if change == "side" || change == "phase" { context[change] = NSNull() }
            let input = CoachingCandidateEngine.Frame.live(source: source, context: context,
                raw3D: change == "nil" ? nil : change == "malformed" ? [] : first.raw3D,
                assessment3D: first.assessment3D, raw2D: first.raw2D, confidence: first.confidence,
                invalid: first.invalid, state: first.state, captureID: change == "capture" ? "new-capture" : first.captureID)
            let next = runtime.process(input, configuration: .success(configuration))
            let clear = try XCTUnwrap(next.clear, change)
            XCTAssertEqual(clear["captureId"] as? String, proposal["captureId"] as? String, change)
            XCTAssertEqual(clear["previousProposalId"] as? String, proposal["proposalId"] as? String, change)
            XCTAssertEqual(clear["source"] as? NSDictionary, proposal["source"] as? NSDictionary, change)
            if ["side", "phase", "malformed", "nil"].contains(change) { XCTAssertNil(next.proposal, change) }
            else { XCTAssertNotNil(next.proposal, change) }
        }
    }

    func testLiveProcessorOffInvalidConfigurationAndSourceGeneration() throws {
        var runtime = CoachingCandidateRuntime.Processor()
        let input = frame(0, "descending", "pushup", sag: 0.5)
        XCTAssertNil(runtime.process(input, configuration: .success(nil)).candidate)
        XCTAssertNotNil(runtime.process(input, configuration: .success(try config("floor"))).proposal)
        let failed = runtime.process(input, configuration: .failure(CoachingCriteria.ValidationError.invalid("test")))
        XCTAssertNotNil(failed.clear); XCTAssertNotNil(failed.error); XCTAssertNil(failed.proposal)
        let session = CoachingCandidateRuntime.SourceSession()
        XCTAssertNil(session.snapshot())
        session.begin(); let old = session.snapshot(); XCTAssertTrue(session.accepts(old))
        session.end(); XCTAssertFalse(session.accepts(old)); XCTAssertFalse(session.accepts(nil))
        session.begin(); XCTAssertFalse(session.accepts(old)); XCTAssertTrue(session.accepts(session.snapshot()))
    }

    func testExportSyntheticLiveSourceTransitionPackets() throws {
        var runtime = CoachingCandidateRuntime.Processor()
        let configuration = try config("floor")
        let initial = runtime.process(frame(0, "descending", "pushup", sag: 0.5, capture: "synthetic-old-source"), configuration: .success(configuration))
        let next = runtime.process(frame(0, "descending", "pushup", sag: 0.5, capture: "synthetic-new-source"), configuration: .success(configuration))
        let proposal = try XCTUnwrap(initial.proposal), clear = try XCTUnwrap(next.clear), newProposal = try XCTUnwrap(next.proposal)
        XCTAssertEqual(clear["captureId"] as? String, "synthetic-old-source")
        XCTAssertEqual(clear["previousProposalId"] as? String, proposal["proposalId"] as? String)
        XCTAssertEqual(newProposal["captureId"] as? String, "synthetic-new-source")
        if let path = ProcessInfo.processInfo.environment["BPT_CANDIDATE_PACKET_OUTPUT"] {
            let fixture: [String: Any] = ["schema": "bpt.synthetic-native-live-source-transition.v1", "synthetic": true,
                "events": [["type": "proposal", "payload": proposal], ["type": "clear", "payload": clear], ["type": "proposal", "payload": newProposal]]]
            try JSONSerialization.data(withJSONObject: fixture, options: [.sortedKeys, .prettyPrinted]).write(to: URL(fileURLWithPath: path))
        }
    }

    func testForcedResetAfterUnknownClearsPresentationCadence() throws {
        var runtime = CoachingCandidateRuntime.Processor()
        let configuration = try config("floor")
        XCTAssertNotNil(runtime.process(frame(0, "descending", "pushup", sag: 0.5), configuration: .success(configuration)).proposal)
        XCTAssertNotNil(runtime.process(frame(1, "descending", "pushup", sag: 0.5, invalid: [3]), configuration: .success(configuration)).clear)
        XCTAssertNil(runtime.reset())
        XCTAssertNotNil(runtime.process(frame(2, "descending", "pushup", sag: 0.5), configuration: .success(configuration)).proposal)
    }

}

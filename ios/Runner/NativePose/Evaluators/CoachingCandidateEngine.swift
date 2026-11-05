import Foundation
import CoreFoundation
import CryptoKit
import simd

/// Stateful causal engineering candidates. These results never alter poses or the default judge.
struct CoachingCandidateEngine {
    typealias JSON = [String: Any]
    static let schema = "bpt.core3-candidate-frame.v1"
    static let evidencePolicy: JSON = ["version": "bpt.candidate-evidence-policy.v1", "sourceIdentity": "capture_epoch", "view": "not_required"]
    struct Configuration {
        let experimentID: String
        let source: String
        let experimentDeclaredAt:String
        let evaluationMode:String
        let variant: String
        var parameters: [String: Double]
        let provenance: [String: String]
        init(experimentID: String, source: String, experimentDeclaredAt:String, evaluationMode:String="causal", variant: String, overrides: JSON = [:], provenance: [String: String] = [:]) throws {
            guard !experimentID.isEmpty, experimentID.utf8.count<=128, !source.isEmpty, source.utf8.count<=1024, !experimentDeclaredAt.isEmpty, experimentDeclaredAt.utf8.count<=128, !variant.isEmpty, variant.utf8.count<=64 else { throw CoachingCriteria.ValidationError.invalid("explicit candidate experiment/variant/source required") }
            self.experimentID = experimentID; self.source = source; self.experimentDeclaredAt=experimentDeclaredAt; self.evaluationMode=evaluationMode; self.variant = variant; self.provenance = provenance
            guard ["causal","offline_declared"].contains(evaluationMode) else {throw CoachingCriteria.ValidationError.invalid("candidate evaluation mode")}
            parameters = Self.defaults
            for (name, raw) in overrides {
                guard Self.parameterNames.contains(name), let value = CoachingCandidateEngine.number(raw) else { throw CoachingCriteria.ValidationError.invalid("unknown/nonfinite candidate parameter") }
                guard provenance[name]?.isEmpty == false else { throw CoachingCriteria.ValidationError.invalid("candidate override provenance required") }
                parameters[name] = value
            }
            for key in ["support.minimumJointScore", "support.maximumAngleCorrection", "window.maximumGapSeconds", "window.squatAscentSeconds", "window.rowRangeSeconds"] {
                guard let value = parameters[key], value > 0 else { throw CoachingCriteria.ValidationError.invalid("positive candidate support/window required") }
            }
            if let value = parameters["support.maximumHipRatioCorrection"], value < 0 { throw CoachingCriteria.ValidationError.invalid("negative ratio tolerance") }
        }
        static var defaults: [String: Double] { (registry["parameters"] as! JSON).compactMapValues { CoachingCandidateEngine.number($0) } }
        static var parameterNames: Set<String> { Set((registry["parameters"] as! JSON).keys) }
    }
    struct Frame {
        let source: JSON
        let context: JSON
        let raw3D: [SIMD3<Double>]?
        let assessment3D: [SIMD3<Double>]?
        let raw2D: [SIMD3<Double>]?
        let confidence: [Double]?
        let invalid: Set<Int>?
        let state: String
        let captureID: String
        var index: Int? { CoachingCandidateEngine.integer(source["source_index"]) }
        var pts: Double? { CoachingCandidateEngine.number(source["source_pts"]) }
        var phase: String? { context["phase"] as? String }
        var side: String? { context["side"] as? String }
        var flush: Bool { CoachingCandidateEngine.yes(context["flush_tail"]) }
        var exercise: String { CoachingCandidateEngine.exercise(context["exercise"] as? String ?? "") }
        /// In-memory production adapter; no logging, serialization, pose mutation or wall clock.
        static func live(source: JSON, context: JSON, raw3D: [SIMD3<Double>]?,
                         assessment3D: [SIMD3<Double>]?, raw2D: [SIMD3<Double>]?,
                         confidence: [Double]?, invalid: Set<Int>?, state: String, captureID: String) -> Frame {
            Frame(source: source, context: context, raw3D: raw3D, assessment3D: assessment3D,
                  raw2D: raw2D, confidence: confidence, invalid: invalid, state: state, captureID: captureID)
        }
        static func terminal(_ row: JSON, exercise: String, captureID: String) -> Frame {
            func vectors(_ value: Any?) -> [SIMD3<Double>]? {
                guard let values = value as? [Any], values.count == 51 else { return nil }
                let nums = values.map { CoachingCandidateEngine.number($0) ?? Double.nan }
                return stride(from: 0, to: 51, by: 3).map { SIMD3(nums[$0], nums[$0+1], nums[$0+2]) }
            }
            let keys = ["frame", "source_index", "source_pts", "source_time_value", "source_time_scale", "time_basis", "epoch"]
            var context: JSON = ["exercise": exercise]
            for key in ["phase", "side", "side_view", "source_kind", "flush_tail", "rotation", "size", "source_mirrored"] { context[key] = row[key] ?? NSNull() }
            let confidence = (row["confidence_h36m"] as? [Any]).flatMap { xs -> [Double]? in let values = xs.map { CoachingCandidateEngine.number($0) ?? Double.nan }; return values.count == 17 ? values : nil }
            let invalid = (row["invalid"] as? [Any]).flatMap { xs -> Set<Int>? in let values = xs.compactMap { CoachingCandidateEngine.integer($0) }; return values.count == xs.count && values.allSatisfy({ 0 <= $0 && $0 < 17 }) ? Set(values) : nil }
            return Frame(source: Dictionary(uniqueKeysWithValues: keys.map { ($0, row[$0] ?? NSNull()) }), context: context,
                         raw3D: vectors(row["raw_3d"]), assessment3D: vectors(row["assessment_3d"]), raw2D: vectors(row["raw_2d"]), confidence: confidence,
                         invalid: invalid, state: row["assessment_state"] as? String ?? "unknown", captureID: captureID)
        }
    }
    struct Measurement {
        var raw: Double?
        var value: Double?
        var reasons: [String]
        var proof: JSON = [:]
        var maximumCorrectionDifference:Double?=nil
        var circular=false
        var available: Bool { raw?.isFinite == true && value?.isFinite == true && reasons.isEmpty }
    }
    private struct Snapshot { let frame: Frame; let metrics: [String: Measurement] }
    private var previous: Snapshot?
    private var pullingStart: Snapshot?
    private var bottomFrames: [Snapshot] = []
    private var bottomEntered = false
    private var ascentStart: Snapshot?
    private var ascentBlocked = false
    private var pullingBlocked = false
    private var rolling: [Snapshot] = []
    private var continuityKey: String?
    private let null = NSNull()
    static func exercise(_ s: String) -> String { ["pushUp": "pushup", "barbellRow": "barbell-row", "barbell_row": "barbell-row", "row": "barbell-row"][s] ?? s }
    static func number(_ x: Any?) -> Double? { guard let n = x as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), let d = Double(n.stringValue), d.isFinite else { return nil }; return d }
    static func integer(_ x: Any?) -> Int? { guard let d = number(x), d >= 0, d <= 9_007_199_254_740_991, let n = x as? NSNumber, !["f", "d"].contains(String(cString: n.objCType)) else { return nil }; return Int(d) }
    static func yes(_ x: Any?) -> Bool { guard let n = x as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }; return n.boolValue }
    private static func unique(_ xs: [String]) -> [String] { var seen = Set<String>(); return xs.filter { seen.insert($0).inserted } }
    private static func wrap(_ value: Double) -> Double { var v = value.truncatingRemainder(dividingBy: 360); if v > 180 { v -= 360 }; if v < -180 { v += 360 }; return v }
    private func reset() -> Self { Self() }
    private static func measured(_ frame: Frame, _ config: Configuration) -> [String: Measurement] {
        var metrics: [String: Measurement] = [:]
        let score = config.parameters["support.minimumJointScore"]!, correction = config.parameters["support.maximumAngleCorrection"]!
        func measure(_ ids: [Int], tolerance: Double?, circular:Bool=false, _ fn: ([SIMD3<Double>]) -> Double?) -> Measurement {
            let raw = frame.raw3D.flatMap(fn), corrected = frame.assessment3D.flatMap(fn); var reasons: [String] = []
            if !["ok", "partial_3d"].contains(frame.state) { reasons.append("unusable_3d") }
            if frame.raw3D?.count != 17 || frame.assessment3D?.count != 17 { reasons.append("missing_geometry") }
            if let invalid = frame.invalid { if !invalid.isDisjoint(with: ids) { reasons.append("invalid_joint") } } else { reasons.append("missing_invalid_mask") }
            if let c = frame.confidence, c.count == 17 { if ids.contains(where: { !c[$0].isFinite || c[$0] < score }) { reasons.append("low_joint_support") } } else { reasons.append("missing_joint_support") }
            if raw?.isFinite != true || corrected?.isFinite != true { reasons.append("missing_or_nonfinite_metric") }
            if let raw, let corrected, let tolerance { let difference=circular ? Self.wrap(raw-corrected):raw-corrected; if !difference.isFinite || abs(difference) > tolerance { reasons.append("raw_assessment_disagreement") } }
            if tolerance == nil { reasons.append("unconfigured_correction_tolerance") }
            if frame.flush { reasons.append("flush_sample_not_observation") }
            return Measurement(raw: raw, value: corrected, reasons: unique(reasons), maximumCorrectionDifference:tolerance,circular:circular)
        }
        for (side, h, k, a, s, e, w) in [("left",4,5,6,11,12,13),("right",1,2,3,14,15,16)] {
            for (name, ids) in [("KneeDeg",[h,k,a]),("HipDeg",[8,h,k]),("ElbowDeg",[s,e,w])] {
                metrics[side+name] = measure(ids, tolerance: correction) { j in guard j.count == 17 else { return nil }; return ExperimentalCoaching.angle(j[ids[0]]-j[ids[1]], j[ids[2]]-j[ids[1]]) }
            }
            metrics[side+"UpperArmDeg"] = measure([0,8,11,14,s,e], tolerance: correction) { j in
                guard j.count == 17, let down = ExperimentalCoaching.unit(j[0]-j[8]), let lateral = ExperimentalCoaching.unit(j[11]-j[14]), let normal = ExperimentalCoaching.unit(simd_cross(down,lateral)) else { return nil }
                let arm = j[e]-j[s]; return ExperimentalCoaching.angle(down,arm-simd_dot(arm,normal)*normal)
            }
        }
        let cameraUp = SIMD3<Double>(0,-1,0)
        metrics["cameraTorsoSignedDeg"] = measure([0,1,4,8], tolerance: correction,circular:true) { j in guard j.count == 17 else { return nil }; return FormGeometry.signedTorsoAngle3D(j, up: cameraUp) }
        metrics["cameraHipLineDeviationRatio"] = measure([0,8,3,6], tolerance: config.parameters["support.maximumHipRatioCorrection"]) { j in guard j.count == 17 else { return nil }; return FormGeometry.signedHipDeviation3D(j, up: cameraUp) }
        // Direct raw detector image heights are not inferred world-space movement.
        let side = frame.side == "left" ? (shoulder:5,hip:11) : (shoulder:6,hip:12)
        var imageReasons: [String] = []
        var hip: Double?, shoulder: Double?, length: Double?
        if frame.side != "left" && frame.side != "right" { imageReasons.append("selected_side_required") }
        if let points = frame.raw2D, points.count == 17 {
            let a=points[side.shoulder], b=points[side.hip]
            if !a.x.isFinite || !a.y.isFinite || !b.x.isFinite || !b.y.isFinite || !a.z.isFinite || !b.z.isFinite || min(a.z,b.z) < score { imageReasons.append("low_or_invalid_raw_2d_support") }
            hip=b.y; shoulder=a.y; length=hypot(a.x-b.x,a.y-b.y)
            if length?.isFinite != true || length! <= 1e-8 { imageReasons.append("degenerate_image_torso") }
        } else { imageReasons.append("missing_raw_detector_2d") }
        if frame.flush { imageReasons.append("flush_sample_not_observation") }
        metrics["imageHipY"] = Measurement(raw:hip,value:hip,reasons:imageReasons)
        metrics["imageShoulderY"] = Measurement(raw:shoulder,value:shoulder,reasons:imageReasons)
        metrics["imageTorsoLength"] = Measurement(raw:length,value:length,reasons:imageReasons)
        return metrics
    }
    mutating func update(_ frame: Frame, configuration config: Configuration, includeRequests: Bool = false) throws -> JSON {
        guard ["pushup","squat","barbell-row"].contains(frame.exercise) else {throw CoachingCriteria.ValidationError.invalid("candidate registry supports core three only")}
        var metrics = Self.measured(frame, config)
        let keyObject: JSON = ["capture":frame.captureID,"epoch":frame.source["epoch"] ?? null,"exercise":frame.exercise,"variant":config.variant,"side":frame.side ?? "unknown","rotation":frame.context["rotation"] ?? null,"size":frame.context["size"] ?? null,"mirror":frame.context["source_mirrored"] ?? null,"sourceKind":frame.context["source_kind"] ?? null,"parameters":config.parameters,"experiment":config.experimentID]
        let key = String(decoding: try JSONSerialization.data(withJSONObject:keyObject,options:[.sortedKeys]),as:UTF8.self)
        let gap = config.parameters["window.maximumGapSeconds"]!
        let continuous: Bool
        if let previous, let t=frame.pts, let old=previous.frame.pts, let i=frame.index, let before=previous.frame.index {
            continuous = key == continuityKey && t>old && t-old<=gap && i==before+1 && !frame.flush && !previous.frame.flush && frame.phase != nil && previous.frame.phase != nil
        } else { continuous=false }
        let resetReasons = continuous ? [] : [previous == nil ? "source_window_initializing" : "source_context_or_continuity_reset"]
        if !continuous { pullingStart=nil; bottomFrames=[]; bottomEntered=false; ascentStart=nil; ascentBlocked=false; rolling=[]; pullingFrames=[]; ascentFrames=[] }
        let snapshot = Snapshot(frame:frame,metrics:metrics)
        let oldPhase = continuous ? previous?.frame.phase : nil
        var completed: [String:Measurement] = [:]
        if frame.phase == "bottom" {
            if oldPhase != "bottom" { bottomFrames=[]; bottomEntered=oldPhase == "descending" }
            bottomFrames.append(snapshot)
            if bottomFrames.count>512 { bottomFrames.removeAll();bottomEntered=false }
        } else if oldPhase == "bottom" {
            if frame.phase == "ascending", bottomEntered, let last=bottomFrames.last {
                ascentStart=last;ascentFrames=[last,snapshot]
                for side in ["left","right"] {
                    for joint in ["Knee","Elbow"] {
                        let name=side+joint+"Deg", source=bottomFrames.compactMap { $0.metrics[name] }
                        let why=Self.unique(source.flatMap(\.reasons))
                        completed[side+joint+"CompletedBottomMinimumDeg"] = Measurement(raw:source.compactMap(\.raw).min(),value:source.compactMap(\.value).min(),reasons:why + (source.count==bottomFrames.count && source.allSatisfy(\.available) ? [] : ["incomplete_bottom_metric_membership"]),proof:windowProof(bottomFrames,kind:"complete_observed_bottom_phase"),maximumCorrectionDifference:config.parameters["support.maximumAngleCorrection"]!)
                    }
                }
            } else { ascentStart=nil;ascentFrames=[] }
            bottomFrames=[];bottomEntered=false
        } else if frame.phase == "ascending", ascentStart != nil { ascentFrames.append(snapshot) }
        if frame.phase != "ascending" { ascentStart=nil;ascentFrames=[] }
        if ascentFrames.count>512 { ascentStart=nil;ascentFrames=[] }
        for (name,value) in completed { metrics[name]=value }
        if frame.phase == "pulling" {
            if oldPhase != "pulling" {
                pullingStart = ["lowering","top","bottom"].contains(oldPhase ?? "") ? snapshot : nil
                pullingFrames = pullingStart == nil ? [] : [snapshot]
            } else if pullingStart != nil { pullingFrames.append(snapshot) }
        } else { pullingStart=nil;pullingFrames=[] }
        if pullingFrames.count>512 { pullingStart=nil;pullingFrames=[] }
        for side in ["left","right"] {
            for (sourceName,derived,invert) in [(side+"KneeDeg",side+"KneeExtensionSincePullStartDeg",false),(side+"ElbowDeg",side+"ElbowFlexionSincePullStartDeg",true)] {
                metrics[derived]=difference(name:sourceName,frames:pullingFrames,invert:invert,kind:"observed_pulling_phase_prefix",bound:2*config.parameters["support.maximumAngleCorrection"]!)
            }
        }
        var torsoRise=difference(name:"cameraTorsoSignedDeg",frames:ascentFrames,invert:false,kind:"observed_bottom_to_ascent_prefix",wrapped:true,bound:2*config.parameters["support.maximumAngleCorrection"]!)
        var imageRise=Measurement(raw:nil,value:nil,reasons:["observed_bottom_to_ascent_anchor_required"])
        if let start=ascentStart, let t=frame.pts, let begin=start.frame.pts {
            let dt=t-begin
            if dt>0 && dt<=config.parameters["window.squatAscentSeconds"]! {
                let inputs=ascentFrames.flatMap { s in [s.metrics["imageHipY"]!,s.metrics["imageShoulderY"]!,s.metrics["imageTorsoLength"]!] }
                let why=Self.unique(inputs.flatMap(\.reasons))
                if let h0=start.metrics["imageHipY"]?.value,let h1=metrics["imageHipY"]?.value,let s0=start.metrics["imageShoulderY"]?.value,let s1=metrics["imageShoulderY"]?.value,let length=start.metrics["imageTorsoLength"]?.value,length>1e-8 {
                    let v=((h0-h1)-(s0-s1))/length/dt
                    imageRise=Measurement(raw:v.isFinite ? v:nil,value:v.isFinite ? v:nil,reasons:why + (v.isFinite ? []:["arithmetic_overflow"]),proof:windowProof(ascentFrames,kind:"raw_detector_2d_initial_torso_normalized_source_rate"),maximumCorrectionDifference:0)
                } else { imageRise.reasons=why+["missing_raw_2d_rate_geometry"] }
            } else { torsoRise.reasons.append("outside_declared_early_ascent_window");imageRise.reasons=["outside_declared_early_ascent_window"] }
        }
        metrics["cameraTorsoRiseFromBottomDeg"]=torsoRise;metrics["imageHipShoulderRiseRateDifference"]=imageRise
        if !frame.flush { rolling.append(snapshot) }
        let duration=config.parameters["window.rowRangeSeconds"]!
        if let t=frame.pts {
            while rolling.count>1,let next=rolling[1].frame.pts,next<=t-duration { rolling.removeFirst() }
        }
        if rolling.count>512 { rolling.removeAll() }
        var range=Measurement(raw:nil,value:nil,reasons:["complete_causal_window_required"])
        if let first=rolling.first?.frame.pts,let last=frame.pts,last-first>=duration,rolling.count>1 {
            let source=rolling.compactMap { $0.metrics["cameraTorsoSignedDeg"] }
            func unwrapped(_ values:[Double])->[Double] { var result:[Double]=[];for value in values { result.append(result.last.map { $0+Self.wrap(value-$0) } ?? value) };return result }
            let raw=unwrapped(source.compactMap(\.raw)),values=unwrapped(source.compactMap(\.value))
            let why=Self.unique(source.flatMap(\.reasons))
            range=Measurement(raw:raw.isEmpty ? nil:raw.max()!-raw.min()!,value:values.isEmpty ? nil:values.max()!-values.min()!,reasons:why + (source.count==rolling.count && source.allSatisfy(\.available) ? []:["incomplete_causal_window_support"]),proof:windowProof(rolling,kind:"rolling_source_pts_bracket_not_whole_rep"),maximumCorrectionDifference:2*config.parameters["support.maximumAngleCorrection"]!)
        }
        metrics["cameraTorsoCausalRangeDeg"]=range
        var outputRules:[JSON]=[],requests:[JSON]=[]
        let rules=Self.registry["rules"] as! [JSON]
        for rule in rules where rule["exercise"] as? String == frame.exercise {
            let ruleID=rule["id"] as! String
            let configuredVariant=(rule["variants"] as? [String] ?? [rule["variant"] as! String]).contains(config.variant)
            var observations:JSON=[:],profiles:JSON=[:],atoms:[JSON]=[],unconfigured:[String]=[]
            for (index,atom) in (rule["atoms"] as! [JSON]).enumerated() {
                let name=(atom["metric"] as! String).replacingOccurrences(of:"{side}",with:frame.side ?? "unknown")
                let id=ruleID+"."+String(index),parameter=atom["parameter"] as! String
                let metric=metrics[name] ?? Measurement(raw:nil,value:nil,reasons:["required_measurement_or_completed_phase_missing"])
                let observation=observation(name:name,metric:metric,frame:frame,config:config)
                observations[id]=observation;atoms.append(["type":"atom","id":id,"observation":id,"profile":id])
                if let target=config.parameters[parameter],configuredVariant {
                    let comparator=atom["comparator"] as! String
                    var identity:JSON=[:];for key in ["metricId","metricVersion","definitionHash","unit","coordinate","aggregation"] { identity[key]=observation[key] ?? null }
                    var review=identity;review["exercise"]=frame.exercise;review["variant"]=config.variant;review["ruleId"]=id
                    var profile=identity
                    profile.merge(["ruleId":id,"exercise":frame.exercise,"variant":config.variant,"comparator":comparator,"referenceKind":"engineering_candidate","predicateMeaning":rule["meaning"] ?? "deviation","revision":Self.registry["revision"]!,"source":config.source,"availableAtPts":0,"evidencePolicy":Self.evidencePolicy,"confirmation":["kind":"caller_declared_engineering_experiment","at":config.experimentDeclaredAt,"reference":config.experimentID,"scope":review],"applicability":["phase":rule["phases"]!,"side":["left","right","bilateral"],"view":["side","front","oblique","unknown"]],"targetParameter":parameter,"targetProvenance":config.provenance[parameter] ?? (Self.registry["parameterSources"] as! JSON)[parameter] ?? "unresolved"],uniquingKeysWith:{$1})
                    profile[["lt","lte"].contains(comparator) ? "lower":"upper"]=target
                    // gte comparator is upper-based in the neutral kernel contract.
                    profiles[id]=profile
                } else { unconfigured.append(configuredVariant ? "unconfigured_parameter:"+parameter:"explicit_supported_variant_required") }
            }
            let request:JSON=["exercise":frame.exercise,"variant":config.variant,"evaluation":["mode":config.evaluationMode,"asOfPts":frame.pts as Any? ?? null],"observations":observations,"profiles":profiles,"criterion":["type":"group","id":ruleID,"op":rule["op"]!,"pairing":["sidePolicy":"bilateral","temporal":rule["temporal"] ?? "simultaneous"],"children":atoms]]
            let result=try CoachingCriteria.evaluate(request),criterion=result["criterion"] as! JSON,children=criterion["children"] as! [JSON]
            let components=children.map { child -> JSON in let id=child["observationId"] as! String,o=observations[id] as! JSON;return ["metric":o["metricId"]!,"state":child["state"]!,"reasons":child["reasons"]!,"rawValue":o["rawValue"]!,"value":o["correctedValue"]!,"evaluatedValue":child["evaluatedValue"] ?? null,"proof":o["measurementProof"] ?? [:]] }
            outputRules.append(["id":ruleID,"state":criterion["state"]!,"meaning":rule["meaning"] ?? "deviation","target":rule["target"]!,"configured":unconfigured.isEmpty,"reasons":Self.unique((criterion["reasons"] as! [String])+unconfigured),"components":components,"partialCoverage":criterion["partialCoverage"]!])
            if includeRequests { requests.append(request) }
        }
        previous=snapshot;continuityKey=key
        var output:JSON=["schema":Self.schema,"captureId":frame.captureID,"evaluationMode":config.evaluationMode,"registryVersion":Self.registry["revision"]!,"authority":"engineering_candidate_not_validated_form","experimentID":config.experimentID,"experimentDeclaredAt":config.experimentDeclaredAt,"variant":config.variant,"source":frame.source,"context":frame.context,"rules":outputRules,"windowResetReasons":resetReasons,"delivered":false,"parameters":config.parameters]
        if includeRequests { output["requests"]=requests }
        return output
    }
    private var pullingFrames:[Snapshot]=[]
    private var ascentFrames:[Snapshot]=[]
    private func windowProof(_ frames:[Snapshot],kind:String)->JSON {
        ["kind":kind,"sourceIndices":frames.map { $0.frame.index as Any? ?? null },"sourcePTS":frames.map { $0.frame.pts as Any? ?? null },"phases":frames.map { $0.frame.phase as Any? ?? null },"completeSupportedMembershipClaim":"each_required_metric_checked_separately","causal":true]
    }
    private func difference(name:String,frames:[Snapshot],invert:Bool,kind:String,wrapped:Bool=false,bound:Double)->Measurement {
        guard frames.count>=2,let first=frames.first?.metrics[name],let last=frames.last?.metrics[name] else { return Measurement(raw:nil,value:nil,reasons:["observed_phase_start_and_later_sample_required"]) }
        let values=frames.compactMap { $0.metrics[name] },why=Self.unique(values.flatMap(\.reasons))
        let raw=first.raw.flatMap { a in last.raw.map { b in invert ? a-b:b-a } },value=first.value.flatMap { a in last.value.map { b in invert ? a-b:b-a } }
        return Measurement(raw:raw.map { wrapped ? Self.wrap($0):$0 },value:value.map { wrapped ? Self.wrap($0):$0 },reasons:why + (values.count==frames.count && values.allSatisfy(\.available) ? []:["incomplete_supported_phase_prefix"]),proof:windowProof(frames,kind:kind),maximumCorrectionDifference:bound,circular:wrapped)
    }
    private func observation(name:String,metric:Measurement,frame:Frame,config:Configuration)->JSON {
        let contract=CoachingCriteria.metricContract(name) ?? [:]
        let side=name.hasPrefix("left") ? "left":name.hasPrefix("right") ? "right":"bilateral"
        let isBottomSummary=name.contains("CompletedBottom")
        let phase=isBottomSummary ? "bottom" as Any:(frame.phase as Any? ?? null),view=Self.yes(frame.context["side_view"]) ? "side":"unknown"
        let indices=metric.proof["sourceIndices"] as? [Any] ?? [], times=metric.proof["sourcePTS"] as? [Any] ?? []
        let isSummary=(contract["temporalKind"] as? String)=="window_summary"
        let sampleIndex=isBottomSummary ? (indices.last ?? null):(frame.index as Any? ?? null)
        let samplePTS=isBottomSummary ? (times.last ?? null):(frame.pts as Any? ?? null)
        let startPTS=isSummary ? (times.first ?? samplePTS):samplePTS, endPTS=isSummary ? (times.last ?? samplePTS):samplePTS
        let support=metric.available
        var why=metric.reasons
        if metric.raw?.isFinite != true || metric.value?.isFinite != true { why.append("missing_or_nonfinite_derived_measurement") }
        let epoch:Any=frame.source["epoch"].flatMap { ($0 is NSNull) ? nil:String(describing:$0) } ?? null
        let scope:JSON=["sourceIdentity":["captureId":frame.captureID,"epoch":epoch,"clockId":"source_pts_seconds"],"timeBasis":frame.source["time_basis"] as? String == "sample_pts_seconds" ? "source_pts_seconds":frame.source["time_basis"] ?? null,"startPts":startPTS,"endPts":endPTS,"side":side,"selectedSide":frame.side as Any? ?? null,"phase":phase,"view":view,"coverageComplete":true,"expectedSourceIndices":[sampleIndex],"coverageEvidence":["phaseStartObserved":true,"phaseEndObserved":true,"membershipSource":"single_actual_derived_sample_with_causal_source_proof"]]
        let raw:Any=metric.raw.flatMap { $0.isFinite ? $0:nil } as Any? ?? null,value:Any=metric.value.flatMap { $0.isFinite ? $0:nil } as Any? ?? null
        let maxDifference:Any=metric.maximumCorrectionDifference as Any? ?? null
        let membership=zip(indices,times).map { ["sourceIndex":$0.0,"pts":$0.1] }
        return ["metricId":name,"metricVersion":contract["version"] ?? null,"definitionHash":contract["definitionHash"] ?? null,"unit":contract["unit"] ?? null,"coordinate":contract["coordinate"] ?? null,"aggregation":"sample","rawValue":raw,"correctedValue":value,"available":support,"blockingReasons":Self.unique(why),"measurementProof":metric.proof,"rawCorrectionDomain":metric.circular ? "circular_degrees":"linear","measurementWindow":["complete":metric.available,"samples":membership],"scope":scope,"support":["requiredJointsSupported":support,"trackingObserved":support,"rawCorrectionChecked":support,"maximumCorrectionDifference":maxDifference],"samples":[["sourceIndex":sampleIndex,"pts":samplePTS,"side":side,"phase":phase,"view":view,"rawValue":raw,"value":value,"available":support,"blockingReasons":Self.unique(why),"flush":frame.flush]]]
    }

    static let registry: JSON = try! JSONSerialization.jsonObject(with: Data(#"""
{"schema": "bpt.core3-technique-candidates.v1", "revision": "20261103-r1", "authority": "engineering_candidate_only_no_expert_approval", "variants": {"pushup": "floor", "squat": "barbell_back_squat", "barbell-row": "strict_bent_over"}, "parameters": {"pushup.cameraSagUpper": 0.14, "pushup.cameraPikeLower": -0.08, "pushup.projectedUpperArmUpper": null, "pushup.bottomElbowUpper": null, "pushup.topElbowLower": null, "squat.torsoRiseUpper": 8, "squat.hipShoulderRiseDifferenceUpper": 0, "squat.bottomKneeUpper": null, "squat.topKneeLower": null, "squat.topHipLower": null, "row.cameraTorsoRangeUpper": 39.9, "row.kneeExtensionLower": null, "row.elbowFlexionLower": null, "support.minimumJointScore": 0.5, "support.maximumAngleCorrection": 10, "support.maximumHipRatioCorrection": null, "window.maximumGapSeconds": 0.25, "window.squatAscentSeconds": 0.3, "window.rowRangeSeconds": 2}, "parameterSources": {"pushup.cameraSagUpper": "PushUpFormConfig.hipSagDeviation=.140; transferred to explicitly camera-up proxy, not identical when native judgement gravity differs", "pushup.cameraPikeLower": "negative PushUpFormConfig.hipPikeDeviation=.08; same transfer limitation", "squat.torsoRiseUpper": "SquatFormConfig.hipsFirstTorsoRiseDegrees=8; new .3s source-PTS ascent interval is not native8-frame window", "squat.hipShoulderRiseDifferenceUpper": "native hipRiseSpeed>shoulderRiseSpeed algebraic zero; same direct 2D height difference normalized by initial torso length/source elapsed time", "row.cameraTorsoRangeUpper": "BarbellRowFormConfig.torsoSwingRangeDegrees=39.9; camera-up rolling window transfer, NOT native whole-rep rule parity", "support.minimumJointScore": "ExperimentalCoaching.minConfidence=.5; score not calibrated probability", "support.maximumAngleCorrection": "ExperimentalCoaching.maxCorrectionDegrees=10; derived angle differences additionally check both endpoint corrections", "window.maximumGapSeconds": "ExperimentalCoaching.maxGapSeconds=.25; a causal evidence continuity policy", "window.squatAscentSeconds": "historical ai/coaching-team docs/coaching/squat.md .3s engineering proposal; does not equal native8frames", "window.rowRangeSeconds": "declared engineering rolling2s interval; not a complete repetition", "unconfigured": "missing parameters require explicit caller engineering values and provenance; no target learned from first reps, literature or rep-count thresholds"}, "rules": [{"id": "pushup.camera_body_line_transfer", "exercise": "pushup", "variant": "floor", "target": "maintain body/pelvis line during active movement; camera proxy, not lumbar/floor contact", "op": "OR", "phases": ["descending", "bottom", "ascending"], "atoms": [{"metric": "cameraHipLineDeviationRatio", "comparator": "gt", "parameter": "pushup.cameraSagUpper"}, {"metric": "cameraHipLineDeviationRatio", "comparator": "lt", "parameter": "pushup.cameraPikeLower"}]}, {"id": "pushup.projected_arm_range", "exercise": "pushup", "variant": "floor", "target": "supplied variant-specific projected upper-arm bound; no anatomical45/60-degree substitution", "op": "OR", "phases": ["descending", "bottom", "ascending"], "atoms": [{"metric": "leftUpperArmDeg", "comparator": "gt", "parameter": "pushup.projectedUpperArmUpper"}, {"metric": "rightUpperArmDeg", "comparator": "gt", "parameter": "pushup.projectedUpperArmUpper"}]}, {"id": "pushup.bottom_target", "exercise": "pushup", "variant": "floor", "target": "supplied elbow minimum target in a completely observed bottom phase; not chest-floor distance", "op": "OR", "phases": ["bottom"], "atoms": [{"metric": "leftElbowCompletedBottomMinimumDeg", "comparator": "gt", "parameter": "pushup.bottomElbowUpper"}, {"metric": "rightElbowCompletedBottomMinimumDeg", "comparator": "gt", "parameter": "pushup.bottomElbowUpper"}], "temporal": "same_window_summary"}, {"id": "pushup.top_extension_target", "exercise": "pushup", "variant": "floor", "target": "both observed elbows meet supplied top angle targets; scoped desired match only", "op": "AND", "meaning": "desired_match", "phases": ["top"], "atoms": [{"metric": "leftElbowDeg", "comparator": "gte", "parameter": "pushup.topElbowLower"}, {"metric": "rightElbowDeg", "comparator": "gte", "parameter": "pushup.topElbowLower"}]}, {"id": "squat.early_ascent_coordination", "exercise": "squat", "variant": "bodyweight", "target": "camera torso rise AND direct image hip rising faster than shoulder in same causal early-ascent interval", "op": "AND", "phases": ["ascending"], "atoms": [{"metric": "cameraTorsoRiseFromBottomDeg", "comparator": "gt", "parameter": "squat.torsoRiseUpper"}, {"metric": "imageHipShoulderRiseRateDifference", "comparator": "gt", "parameter": "squat.hipShoulderRiseDifferenceUpper"}], "temporal": "same_window_summary", "variants": ["bodyweight", "barbell_back_squat"]}, {"id": "squat.bottom_target", "exercise": "squat", "variant": "bodyweight", "target": "supplied knee minimum target in a completely observed bottom phase; not absolute floor/thigh depth", "op": "OR", "phases": ["bottom"], "atoms": [{"metric": "leftKneeCompletedBottomMinimumDeg", "comparator": "gt", "parameter": "squat.bottomKneeUpper"}, {"metric": "rightKneeCompletedBottomMinimumDeg", "comparator": "gt", "parameter": "squat.bottomKneeUpper"}], "temporal": "same_window_summary", "variants": ["bodyweight", "barbell_back_squat"]}, {"id": "squat.top_extension_target", "exercise": "squat", "variant": "bodyweight", "target": "selected anatomical side knee AND thorax8-hip-knee interior angle meet supplied targets; not native shoulder-hip-knee alias", "op": "AND", "meaning": "desired_match", "phases": ["top"], "selectedSideAtoms": true, "atoms": [{"metric": "{side}KneeDeg", "comparator": "gte", "parameter": "squat.topKneeLower"}, {"metric": "{side}HipDeg", "comparator": "gte", "parameter": "squat.topHipLower"}], "variants": ["bodyweight", "barbell_back_squat"]}, {"id": "row.camera_torso_window_transfer", "exercise": "barbell-row", "variant": "strict_bent_over", "target": "camera torso excursion in complete declared causal rolling window; not native whole-rep swing", "op": "OR", "phases": ["pulling", "lowering"], "atoms": [{"metric": "cameraTorsoCausalRangeDeg", "comparator": "gt", "parameter": "row.cameraTorsoRangeUpper"}], "temporal": "same_window_summary"}, {"id": "row.phase_prefix_leg_arm_cooccurrence", "exercise": "barbell-row", "variant": "strict_bent_over", "target": "both knees extend AND both elbows flex over identical observed pulling-phase prefix; co-occurrence, not instantaneous coincidence, force or intentional cheating", "op": "AND", "phases": ["pulling"], "atoms": [{"metric": "leftKneeExtensionSincePullStartDeg", "comparator": "gte", "parameter": "row.kneeExtensionLower"}, {"metric": "rightKneeExtensionSincePullStartDeg", "comparator": "gte", "parameter": "row.kneeExtensionLower"}, {"metric": "leftElbowFlexionSincePullStartDeg", "comparator": "gte", "parameter": "row.elbowFlexionLower"}, {"metric": "rightElbowFlexionSincePullStartDeg", "comparator": "gte", "parameter": "row.elbowFlexionLower"}], "temporal": "same_window_summary"}]}
"""#.utf8)) as! JSON
}

import Foundation
import CoreFoundation
import CryptoKit

/// Pure, bounded, observation-only JSON contract. No I/O, model/default thresholds,
/// delivery, or inference of approval/whole-form/clinical correctness.
enum CoachingCriteria {
    typealias JSON = [String: Any]
    enum ValidationError: Error { case invalid(String) }
    private static let null = NSNull()
    private static let identityKeys = ["metricId", "metricVersion", "definitionHash", "unit", "coordinate", "aggregation"]
    private static let contextKeys = ["sourceIdentity", "timeBasis", "startPts", "endPts", "phase", "side", "selectedSide", "view"]
    private static let sourceKeys = ["inputSha256", "sourceCommit", "modelSha256", "epoch", "clockId"]
    private static let phases = ["top", "bottom", "descending", "ascending", "pulling", "lowering", "rising", "set", "rep"]
    private static let sides = ["left", "right", "bilateral"]
    private static let views = ["side", "front", "oblique"]
    private static let kinds = ["explicit_target": "scoped_target_predicate", "engineering_candidate": "candidate_predicate", "observed_first3": "relative_change_predicate"]
    private static func value(_ x: Any?) -> Any { x ?? null }
    private static func dict(_ x: Any?) -> JSON { x as? JSON ?? [:] }
    private static func list(_ x: Any?) -> [Any] { x as? [Any] ?? [] }
    private static func isBool(_ x: Any?) -> Bool { guard let n = x as? NSNumber else { return false }; return CFGetTypeID(n) == CFBooleanGetTypeID() }
    private static func yes(_ x: Any?) -> Bool { isBool(x) && (x as? NSNumber)?.boolValue == true }
    private static func number(_ x: Any?) -> Double? { guard !isBool(x), let n = x as? NSNumber, let result = Double(n.stringValue), result.isFinite else { return nil }; return result }
    private static func integer(_ x: Any?) -> Int? {
        guard let n = number(x), abs(n) <= 9_007_199_254_740_991, let boxed = x as? NSNumber,
              !["f", "d"].contains(String(cString: boxed.objCType)) else { return nil }
        return Int(n)
    }
    private static func eq(_ a: Any?, _ b: Any?) -> Bool { (value(a) as AnyObject).isEqual(value(b)) }
    private static func member(_ x: Any?, _ allowed: [String]) -> Bool { guard let s = x as? String else { return false }; return allowed.contains(s) }
    private static func nonempty(_ x: Any?) -> Bool { (x as? String)?.isEmpty == false }
    private static func unique(_ xs: [String]) -> [String] { var seen = Set<String>(); return xs.filter { seen.insert($0).inserted } }
    private static func identity(_ x: JSON) -> JSON { Dictionary(uniqueKeysWithValues: identityKeys.map { ($0, value(x[$0])) }) }
    private static func context(_ x: Any?) -> JSON { let s = dict(dict(x)["scope"]); if dict(x)["scope"] != nil && !(dict(x)["scope"] is JSON) { return [:] }; return Dictionary(uniqueKeysWithValues: contextKeys.map { ($0, value(s[$0])) }) }
    private static func points(_ x: Any?) -> [JSON] { list(x).compactMap { $0 as? JSON } }
    private struct Point: Hashable, Comparable {
        let index: Int; let pts: Double
        static func < (a: Point, b: Point) -> Bool { a.index == b.index ? a.pts < b.pts : a.index < b.index }
        var json: JSON { ["sourceIndex": index, "pts": pts] }
    }
    private static func pointSet(_ x: Any?) -> Set<Point> { Set(points(x).compactMap { x in guard let i = integer(x["sourceIndex"]), let t = number(x["pts"]) else { return nil }; return Point(index: i, pts: t) }) }
    private static func predicate(_ n: Double, _ p: JSON) -> Bool {
        let lo = number(p["lower"]) ?? 0, hi = number(p["upper"]) ?? 0
        switch p["comparator"] as? String { case "gt": return n > hi; case "gte": return n >= hi; case "lt": return n < lo; case "lte": return n <= lo; case "inside": return lo <= n && n <= hi; case "outside": return n < lo || n > hi; default: return false }
    }
    private static func boundsValid(_ p: JSON) -> Bool {
        if member(p["comparator"], ["gt", "gte"]) { return number(p["upper"]) != nil }
        if member(p["comparator"], ["lt", "lte"]) { return number(p["lower"]) != nil }
        return member(p["comparator"], ["inside", "outside"]) && number(p["lower"]) != nil && number(p["upper"]) != nil && number(p["lower"])! <= number(p["upper"])!
    }
    private static func coverage(_ o: JSON, _ samples: [JSON]) -> Bool {
        let s = dict(o["scope"]), e = dict(s["coverageEvidence"]), expected = list(s["expectedSourceIndices"])
        let indices = samples.compactMap { integer($0["sourceIndex"]) }
        return yes(e["phaseStartObserved"]) && yes(e["phaseEndObserved"]) && nonempty(e["membershipSource"]) && yes(s["coverageComplete"]) && !expected.isEmpty && expected.allSatisfy { integer($0) != nil } && eq(expected, samples.map { value($0["sourceIndex"]) }) && Set(indices).count == indices.count && indices.count == samples.count && samples.allSatisfy { yes($0["available"]) && number($0["value"]) != nil && !yes($0["flush"]) } && zip(indices, indices.dropFirst()).allSatisfy { $0 + 1 == $1 }
    }
    private static func sampleReasons(_ o: JSON, _ samples: [JSON]) -> [String] {
        let s = dict(o["scope"]), source = dict(s["sourceIdentity"]); var r: [String] = []
        if !sourceKeys.allSatisfy({ nonempty(source[$0]) }) { r.append("complete_source_identity_required") }
        if !member(s["selectedSide"], sides) { r.append("selected_side_required") }
        if !eq(s["timeBasis"], "source_pts_seconds") { r.append("source_pts_time_basis_required") }
        if number(s["startPts"]) == nil || number(s["endPts"]) == nil || number(s["startPts"])! > number(s["endPts"])! { r.append("invalid_window_boundaries") }
        if !member(s["phase"], phases) || !member(s["side"], sides) || !member(s["view"], views) { r.append("unknown_observation_context") }
        let indices = samples.compactMap { integer($0["sourceIndex"]) }
        if indices.count != samples.count || indices.contains(where: { $0 < 0 }) || Set(indices).count != indices.count || !zip(indices, indices.dropFirst()).allSatisfy({ $0 < $1 }) { r.append("invalid_or_duplicate_source_indices") }
        var previous: Double?
        for x in samples {
            let t = number(x["pts"])
            if t == nil || previous.map({ t! <= $0 }) == true { r.append("nonmonotonic_or_invalid_source_pts") }
            if let t, let start = number(s["startPts"]), let end = number(s["endPts"]), !(start <= t && t <= end) { r.append("sample_outside_window") }
            if yes(x["flush"]) { r.append("flush_sample_not_observation") }
            if ["side", "phase", "view"].contains(where: { !eq(x[$0], s[$0]) }) { r.append("context_transition_in_window") }
            previous = t
        }
        return unique(r)
    }
    // Match Python's sorted, compact, ensure_ascii profile fingerprint.
    private static func canonicalJSON(_ x: Any) throws -> String {
        if x is NSNull { return "null" }
        if isBool(x) { return yes(x) ? "true" : "false" }
        if let n = x as? NSNumber {
            let kind = String(cString: n.objCType)
            if !["f", "d"].contains(kind) { return n.stringValue }
            let double = Double(n.stringValue)!
            var result = String(double)
            if let e = result.firstIndex(of: "e") {
                var mantissa = String(result[..<e]); if mantissa.hasSuffix(".0") { mantissa.removeLast(2) }
                let exponent = Int(result[result.index(after: e)...])!
                if exponent >= -4 && exponent < 16 { 
                    let negative = mantissa.hasPrefix("-"); let unsigned = negative ? String(mantissa.dropFirst()) : mantissa
                    let digits = unsigned.replacingOccurrences(of: ".", with: "")
                    let position = exponent + 1
                    let decimal: String
                    if position <= 0 { decimal = "0." + String(repeating: "0", count: -position) + digits }
                    else if position >= digits.count { decimal = digits + String(repeating: "0", count: position - digits.count) + ".0" }
                    else { let point = digits.index(digits.startIndex, offsetBy: position); decimal = String(digits[..<point]) + "." + String(digits[point...]) }
                    return (negative ? "-" : "") + decimal
                 }
                result = mantissa + "e" + (exponent < 0 ? "-" : "+") + String(format: "%02d", abs(exponent))
            }
            return result
        }
        if let s = x as? String {
            let data = try JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed, .withoutEscapingSlashes])
            let escaped = String(decoding: data, as: UTF8.self)
            return escaped.utf16.map { unit in unit >= 128 ? String(format: "\\u%04x", unit) : String(UnicodeScalar(unit)!) }.joined()
        }
        if let xs = x as? [Any] { return "[" + (try xs.map { try canonicalJSON($0) }).joined(separator: ",") + "]" }
        let d = x as! JSON
        return "{" + (try d.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { try canonicalJSON($0) + ":" + canonicalJSON(d[$0]!) }).joined(separator: ",") + "}"
    }
    private static func assess(_ node: JSON, _ request: JSON, _ observations: JSON, _ profiles: JSON) throws -> JSON {
        let id = node["id"] as! String, observationID = node["observation"] as! String
        let original = observations[observationID], profileID = node["profile"] as? String, originalProfile = profileID.flatMap { profiles[$0] }
        var out: JSON = ["id": id, "type": "atom", "state": "unknown", "reasons": [String](), "observationId": observationID, "observed": value(original), "profileId": value(node["profile"]), "profile": value(originalProfile), "partialCoverage": false, "interpretation": "unresolved", "scope": context(original), "knownComponents": [String]()]
        var r: [String] = []
        func finish(_ reasons: [String]) -> JSON { var result = out; result["reasons"] = reasons; return result }
        guard let original, !(original is NSNull) else { return finish(["missing_observation"]) }
        guard let o = original as? JSON else { return finish(["malformed_observation"]) }
        guard let scope = o["scope"] as? JSON else { return finish(["malformed_observation_scope"]) }
        let spec = (o["metricId"] as? String).flatMap { catalog[$0] as? JSON }
        if spec == nil { r.append("unknown_metric_definition") }
        else if !list(spec!["exercises"]).contains(where: { eq($0, request["exercise"]) }) { out["state"] = "not_applicable"; return finish(["metric_not_applicable_to_exercise"]) }
        let support = dict(o["support"])
        if eq(o["metricId"], "trunkInclineDeg") && !yes(support["gravitySynchronized"]) { r.append("synchronized_source_gravity_required") }
        if let spec {
            for (k, key) in [("metricVersion", "version"), ("definitionHash", "definitionHash"), ("unit", "unit"), ("coordinate", "coordinate")] where !eq(o[k], spec[key]) { r.append("observation_" + k + "_mismatch") }
        }
        if !member(o["aggregation"], ["sample", "max", "min", "rom", "delta"]) { r.append("unsupported_aggregation") }
        if !yes(o["available"]) { r.append("observation_unavailable") }
        if let blocking = o["blockingReasons"] { if let xs = blocking as? [String] { r += xs } else { r.append("invalid_blocking_reasons") } }
        var samples: [JSON] = []
        if let rawSamples = o["samples"] { if let xs = rawSamples as? [JSON] { samples = xs } else { r.append("invalid_samples") } }
        r += sampleReasons(o, samples)
        let evaluation = dict(request["evaluation"])
        if !member(evaluation["mode"], ["causal", "offline_declared"]) || number(evaluation["asOfPts"]) == nil { r.append("explicit_evaluation_clock_required") }
        else if number(scope["endPts"]) == nil || number(scope["endPts"])! > number(evaluation["asOfPts"])! { r.append("future_observation_window") }
        if samples.isEmpty { r.append("actual_samples_required") }
        for check in ["requiredJointsSupported", "trackingObserved", "rawCorrectionChecked"] where !yes(support[check]) { r.append("support_" + check + "_required") }
        let correction = number(support["maximumCorrectionDifference"])
        if correction == nil || correction! < 0 { r.append("explicit_correction_limit_required") }
        var evidence: [JSON] = []
        for x in samples {
            var why: [String] = []
            if !yes(x["available"]) { why.append("sample_unavailable") }
            if let blocking = x["blockingReasons"] { if let xs = blocking as? [String] { why += xs } else { why.append("invalid_sample_blocking_reasons") } }
            if isBool(x["rawValue"]) || isBool(x["value"]) { r.append("boolean_numeric_sample_rejected") }
            if let raw = number(x["rawValue"]), let corrected = number(x["value"]) { if let correction, abs(raw - corrected) > correction { why.append("raw_correction_disagreement") } }
            else { why.append("invalid_supported_raw_or_corrected_sample") }
            evidence.append(["sourceIndex": value(x["sourceIndex"]), "pts": value(x["pts"]), "supported": why.isEmpty, "reasons": why])
        }
        out["sampleEvidence"] = evidence
        guard let originalProfile, !(originalProfile is NSNull) else { r.append("profile_required"); return finish(r) }
        guard let p = originalProfile as? JSON else { r.append("malformed_profile"); return finish(r) }
        let canonical = Data(try canonicalJSON(p).utf8)
        out["profileIntegrityHash"] = SHA256.hash(data: canonical).map { String(format: "%02x", $0) }.joined()
        out["predicateMeaning"] = value(p["predicateMeaning"])
        if !member(p["predicateMeaning"], ["deviation", "desired_match"]) { r.append("predicate_meaning_required") }
        let kind = p["referenceKind"] as? String
        out["interpretation"] = kind.flatMap { kinds[$0] } ?? "unresolved"
        if kind == nil || kinds[kind!] == nil { r.append("unresolved_reference_kind") }
        for key in identityKeys where !eq(p[key], o[key]) { r.append("profile_" + key + "_mismatch") }
        for key in ["exercise", "variant"] where !eq(p[key], request[key]) { r.append("profile_" + key + "_mismatch") }
        if !eq(p["ruleId"], id) { r.append("profile_rule_mismatch") }
        if !nonempty(p["revision"]) { r.append("profile_revision_required") }
        if !nonempty(p["source"]) { r.append("profile_source_required") }
        let confirmation = dict(p["confirmation"]), review = dict(confirmation["scope"])
        if !nonempty(confirmation["kind"]) || !nonempty(confirmation["at"]) || !nonempty(confirmation["reference"]) { r.append("confirmation_metadata_required") }
        var expected = identity(o); expected["exercise"] = value(request["exercise"]); expected["variant"] = value(request["variant"]); expected["ruleId"] = id
        if expected.contains(where: { !eq(review[$0.key], $0.value) }) { r.append("review_scope_mismatch_or_missing") }
        for key in ["phase", "side", "view"] {
            let allowed = dict(p["applicability"])[key] as? [String], allowedEnum = key == "phase" ? phases : key == "side" ? sides : views
            if allowed == nil || allowed!.isEmpty || allowed!.contains(where: { !allowedEnum.contains($0) }) { r.append("profile_" + key + "_scope_required") }
            else if !allowed!.contains(where: { eq($0, scope[key]) }) { r.append("outside_profile_" + key + "_scope") }
        }
        if !boundsValid(p) { r.append("invalid_or_nonfinite_bounds") }
        if number(p["availableAtPts"]) == nil || number(scope["startPts"]) == nil || number(p["availableAtPts"])! > number(scope["startPts"])! { r.append("future_or_unknown_profile_availability") }
        var offset: Double = 0
        if kind == "observed_first3" {
            let refs = p["references"] as? [JSON] ?? []; var valid = refs.count == 3
            if valid {
                let ids = refs.compactMap { $0["id"] as? String }, ends = refs.compactMap { number($0["endPts"]) }
                valid = ids.count == 3 && ids.allSatisfy { !$0.isEmpty } && Set(ids).count == 3 && ends.count == 3 && refs.allSatisfy { integer($0["repIndex"]) != nil } && eq(refs.map { value($0["repIndex"]) }, [1,2,3]) && zip(ends, ends.dropFirst()).allSatisfy { $0 < $1 } && number(scope["startPts"]) != nil && ends.last.map { $0 < number(scope["startPts"])! } == true
                valid = valid && refs.allSatisfy { x in number(x["value"]) != nil && yes(x["available"]) && yes(x["coverageComplete"]) && eq(identity(x), identity(o)) && x["context"] is JSON && ["sourceIdentity", "selectedSide", "side", "phase", "view"].allSatisfy { eq(dict(x["context"])[$0], scope[$0]) } }
            }
            if !valid { r.append("invalid_incomplete_or_future_first3_reference") }
            else { offset = refs.compactMap { number($0["value"]) }.sorted()[1]; out["referenceIds"] = refs.map { value($0["id"]) }; out["referenceValue"] = offset }
        }
        r = unique(r)
        if !r.isEmpty { if r.allSatisfy({ $0.hasPrefix("outside_profile_") }) { out["state"] = "not_applicable" }; return finish(r) }
        let good = zip(samples, evidence).filter { yes($0.1["supported"]) }.map { $0.0 }
        let full = coverage(o, samples) && good.count == samples.count; out["partialCoverage"] = !full
        if good.isEmpty { return finish(["no_supported_actual_sample"]) }
        let aggregation = o["aggregation"] as! String, values = good.compactMap { number($0["value"]) }
        if ["min", "rom", "delta"].contains(aggregation) && !full { return finish(["complete_phase_span_required"]) }
        if aggregation == "sample" && samples.count != 1 { return finish(["sample_aggregation_requires_one_sample"]) }
        let base: Double
        switch aggregation { case "sample": base = values.last!; case "max": base = values.max()!; case "min": base = values.min()!; case "rom": base = values.max()! - values.min()!; default: base = values.last! - values.first! }
        let evaluated = base - offset
        if !evaluated.isFinite || values.contains(where: { !($0 - offset).isFinite }) || !(number(scope["endPts"])! - number(scope["startPts"])!).isFinite { return finish(["arithmetic_overflow"]) }
        out["evaluatedValue"] = evaluated; out["aggregation"] = aggregation
        out["sampleMembership"] = samples.map { ["sourceIndex": value($0["sourceIndex"]), "pts": value($0["pts"])] }
        out["supportedPositiveSamples"] = good.filter { predicate(number($0["value"])! - offset, p) }.map { ["sourceIndex": value($0["sourceIndex"]), "pts": value($0["pts"])] }
        var result = predicate(evaluated, p)
        if aggregation == "max" && !full && !(result && member(p["comparator"], ["gt", "gte"])) { return finish(["complete_span_required_for_max_nonpositive_or_bounded_claim"] + unique(evidence.flatMap { $0["reasons"] as? [String] ?? [] })) }
        let sustain = number(p["sustainSeconds"] ?? 0)
        if sustain == nil || sustain! < 0 { return finish(["invalid_sustain_duration"]) }
        if sustain! > 0 {
            if !["sample", "max"].contains(aggregation) { return finish(["sustain_requires_sample_predicate"]) }
            guard let gap = number(p["maximumGapSeconds"]), gap > 0 else { return finish(["explicit_maximum_gap_required"]) }
            var longest: Double = 0, begin: Double?, previous: JSON?
            var run: [JSON] = [], qualifying: [JSON] = []
            func closeRun() { if let first = run.first, let last = run.last, number(last["pts"])! - number(first["pts"])! >= sustain! { qualifying += run }; run = []; begin = nil }
            for (x, e) in zip(samples, evidence) {
                let valid = yes(e["supported"]) && predicate(number(x["value"])! - offset, p)
                let t = number(x["pts"])!, i = integer(x["sourceIndex"])!
                let contiguous = previous.map { t - number($0["pts"])! <= gap && i == integer($0["sourceIndex"])! + 1 } ?? false
                if !valid || !contiguous { closeRun() }
                if valid { if begin == nil { begin = t }; run.append(x) }
                if let begin { longest = max(longest, t - begin) }; previous = x
            }
            closeRun()
            out["supportedPositiveSamples"] = qualifying.map { ["sourceIndex": value($0["sourceIndex"]), "pts": value($0["pts"])] }
            out["supportedDurationSeconds"] = longest; result = longest >= sustain!
            let hasGap = zip(samples, samples.dropFirst()).contains { number($1["pts"])! - number($0["pts"])! > gap || integer($1["sourceIndex"])! != integer($0["sourceIndex"])! + 1 }
            if !result && (!full || hasGap || number(scope["endPts"])! - number(scope["startPts"])! < sustain!) { return finish(["incomplete_sustain_coverage"]) }
        }
        out["state"] = result ? "positive_evidence" : "negative_evidence"; return finish([])
    }

    // Pinned metric identities generated from the public v1 catalog, never targets.
    private static let catalog: JSON = try! JSONSerialization.jsonObject(with: Data(#"""
{"rightKneeDeg":{"metricId":"rightKneeDeg","version":"1","unit":"degrees","coordinate":"XS_H36M17_model_space_body_relative","definition":"interior_angle_deg_h36m17_(1, 2, 3)","exercises":["pushup","squat","barbell-row"],"definitionHash":"fe8540b0fe46e9ea042887fa01ce0022abcd93cd0c83edb5320061c2a73a52f9"},"rightHipDeg":{"metricId":"rightHipDeg","version":"1","unit":"degrees","coordinate":"XS_H36M17_model_space_body_relative","definition":"interior_angle_deg_h36m17_(8, 1, 2)","exercises":["pushup","squat","barbell-row"],"definitionHash":"800992f8ba2e1093a724d1a79851d29145e1f4554efe836568303c9c2f5eb41e"},"rightElbowDeg":{"metricId":"rightElbowDeg","version":"1","unit":"degrees","coordinate":"XS_H36M17_model_space_body_relative","definition":"interior_angle_deg_h36m17_(14, 15, 16)","exercises":["pushup","barbell-row"],"definitionHash":"ec8f0ce805130187818ceae25c3819708bc5bd2f38c8e05b073863c26f66a5a3"},"rightUpperArmDeg":{"metricId":"rightUpperArmDeg","version":"1","unit":"degrees","coordinate":"XS_H36M17_model_space_body_relative","definition":"angle_of_right_upper_arm_projected_into_body_frontal_plane_from_caudal_trunk_axis; not anatomical shoulder elevation","exercises":["pushup"],"definitionHash":"11aa69ccd7d1be579434bb65ad8672cf52cf200c8dfb626ffffa46b0d7958879"},"leftKneeDeg":{"metricId":"leftKneeDeg","version":"1","unit":"degrees","coordinate":"XS_H36M17_model_space_body_relative","definition":"interior_angle_deg_h36m17_(4, 5, 6)","exercises":["pushup","squat","barbell-row"],"definitionHash":"8eb25b4048b0155ef38102d5573d00593778bd58e3158b986ce09e7660a39cae"},"leftHipDeg":{"metricId":"leftHipDeg","version":"1","unit":"degrees","coordinate":"XS_H36M17_model_space_body_relative","definition":"interior_angle_deg_h36m17_(8, 4, 5)","exercises":["pushup","squat","barbell-row"],"definitionHash":"db68307ad358833c5324c58e083a71ffd990923ef1db52df8e079423cb6a0352"},"leftElbowDeg":{"metricId":"leftElbowDeg","version":"1","unit":"degrees","coordinate":"XS_H36M17_model_space_body_relative","definition":"interior_angle_deg_h36m17_(11, 12, 13)","exercises":["pushup","barbell-row"],"definitionHash":"01a12e9bc854c2d7f8011b6aeeae9052915c5b417ef451b820b6d28791fd7391"},"leftUpperArmDeg":{"metricId":"leftUpperArmDeg","version":"1","unit":"degrees","coordinate":"XS_H36M17_model_space_body_relative","definition":"angle_of_left_upper_arm_projected_into_body_frontal_plane_from_caudal_trunk_axis; not anatomical shoulder elevation","exercises":["pushup"],"definitionHash":"bd6e0ce9848cf9a2feeb800ce6bccd377298a6b2090f400a6500e3d7ebf9fea6"},"trunkInclineDeg":{"metricId":"trunkInclineDeg","version":"1","unit":"degrees","coordinate":"source_synchronized_up_required","definition":"angle_pelvis0_to_thorax8_vs_verified_synchronized_source_gravity; not lumbar curvature","exercises":["pushup","squat","barbell-row"],"definitionHash":"1c7c816fdde410b3ec24cf14f281852ae439e351d59207fb8f5a9554019c8bdc"},"cameraTorsoSignedDeg":{"metricId":"cameraTorsoSignedDeg","version":"1","unit":"degrees","coordinate":"XS_H36M17_camera_reference_no_verified_ground","definition":"FormGeometry.signedTorsoAngle3D pelvis0\u2192thorax8 vs camera up (0,-1,0), hip-defined forward signed; not verified gravity or lumbar angle","exercises":["pushup","squat","barbell-row"],"definitionHash":"7771c04dc4512346c1d913a33ec5ca971241d443f10dc05b2044a3376cfe7f93"},"cameraHipLineDeviationRatio":{"metricId":"cameraHipLineDeviationRatio","version":"1","unit":"dimensionless_ratio","coordinate":"XS_H36M17_camera_reference_no_verified_ground","definition":"FormGeometry.signedHipDeviation3D hip0 vs thorax8\u2192ankleMid(3,6), signed camera-up projection / line length; not floor contact","exercises":["pushup"],"definitionHash":"b1fd69d1a1359dac36ae6ad1466b2275aa50399985739b5325d4557373dc8a31"}}
"""#.utf8)) as! JSON

    static func metricContract(_ name: String) -> JSON? { catalog[name] as? JSON }

    private static func validateJSON(_ x: Any, depth: Int = 0, count: inout Int) throws {
        count += 1
        guard depth <= 64, count <= 100_000 else { throw ValidationError.invalid("JSON structural budget exceeded") }
        if x is NSNull || x is String { return }
        if let n = x as? NSNumber { guard n.doubleValue.isFinite else { throw ValidationError.invalid("nonfinite JSON number") }; return }
        if let xs = x as? [Any] { for child in xs { try validateJSON(child, depth: depth + 1, count: &count) }; return }
        if let d = x as? JSON { for child in d.values { try validateJSON(child, depth: depth + 1, count: &count) }; return }
        throw ValidationError.invalid("non JSON value")
    }
    private static func validateTree(_ raw: Any?, depth: Int = 0, ids: inout Set<String>) throws -> JSON {
        guard depth <= 16, ids.count < 128, let node = raw as? JSON, let id = node["id"] as? String,
              !id.isEmpty, ids.insert(id).inserted else { throw ValidationError.invalid("criterion structural budget or id") }
        if eq(node["type"], "atom"), node["observation"] is String {
            guard node["profile"] == nil || node["profile"] is NSNull || node["profile"] is String else { throw ValidationError.invalid("profile id must be string or null") }
            return node
        }
        guard eq(node["type"], "group"), member(node["op"], ["AND", "OR"]), let children = node["children"] as? [Any], !children.isEmpty else { throw ValidationError.invalid("invalid typed criterion") }
        for child in children { _ = try validateTree(child, depth: depth + 1, ids: &ids) }
        return node
    }
    static func evaluate(_ request: JSON) throws -> JSON {
        var count = 0; try validateJSON(request, count: &count)
        guard request["observations"] == nil || request["observations"] is JSON, request["profiles"] == nil || request["profiles"] is JSON else { throw ValidationError.invalid("observations/profiles must be objects") }
        var ids = Set<String>(); let tree = try validateTree(request["criterion"], ids: &ids)
        let observations = dict(request["observations"]), profiles = dict(request["profiles"])
        func visit(_ node: JSON) throws -> JSON {
            if eq(node["type"], "atom") { return try assess(node, request, observations, profiles) }
            let children = try (node["children"] as! [JSON]).map { try visit($0) }
            let active = children.filter { !eq($0["state"], "not_applicable") }, states = active.compactMap { $0["state"] as? String }
            let pairingRaw = node["pairing"] ?? [:], pairing = dict(pairingRaw), op = node["op"] as! String
            let scope = active.first?["scope"] as? JSON
            let validPairing = pairingRaw is JSON && member(pairing["sidePolicy"], ["same_selected_side", "bilateral"]) && member(pairing["temporal"], ["simultaneous", "same_window_summary"])
            let keys = contextKeys.filter { !(eq(pairing["sidePolicy"], "bilateral") && $0 == "side") }
            var compatible = validPairing && active.allSatisfy { child in guard let scope, let other = child["scope"] as? JSON else { return false }; return keys.allSatisfy { eq(other[$0], scope[$0]) } }
            if compatible && eq(pairing["temporal"], "same_window_summary") { compatible = !list(active.first?["sampleMembership"]).isEmpty && active.allSatisfy { eq($0["sampleMembership"], active.first?["sampleMembership"]) } }
            var reasons: [String] = [], common: Set<Point>?
            if op == "AND" && !validPairing { reasons.append("explicit_component_pairing_required") }
            if compatible && eq(pairing["temporal"], "simultaneous") {
                func summaryEvidence(_ child: JSON) -> Bool {
                    if eq(child["type"], "atom") { return !member(child["aggregation"], ["sample", "max"]) }
                    return points(child["children"]).filter { eq($0["state"], "positive_evidence") }.contains { summaryEvidence($0) }
                }
                if active.contains(where: { summaryEvidence($0) }) { compatible = false; reasons.append("summary_metric_requires_same_window_contract") }
                for child in active { let samples = pointSet(child["supportedPositiveSamples"]); common = common.map { $0.intersection(samples) } ?? samples }
            }
            let knownScopes = active.compactMap { $0["scope"] as? JSON }.filter { x in guard let source = x["sourceIdentity"] as? JSON else { return false }; return sourceKeys.allSatisfy { nonempty(source[$0]) } }
            let knownConflict = knownScopes.dropFirst().contains { other in keys.contains { !eq(other[$0], knownScopes[0][$0]) } }
            if knownConflict { reasons.append("conflicting_known_component_contexts") }
            let membershipChildren = op == "OR" && !knownConflict ? active.filter { eq($0["state"], "positive_evidence") } : active
            var membership = membershipChildren.first?["sampleMembership"]
            if list(membership).isEmpty || membershipChildren.contains(where: { !eq($0["sampleMembership"], membership) }) { membership = nil }
            let state: String
            if active.isEmpty { state = "not_applicable" }
            else if op == "AND" {
                if !compatible { state = "unknown"; reasons.append("noncoincident_component_scopes") }
                else if states.contains("negative_evidence") { state = "negative_evidence" }
                else if states.allSatisfy({ $0 == "positive_evidence" }) {
                    if eq(pairing["temporal"], "simultaneous") && (common?.isEmpty ?? true) { state = "unknown"; reasons.append("no_shared_supported_positive_sample") }
                    else { state = "positive_evidence" }
                } else { state = "unknown" }
            } else { state = knownConflict ? "unknown" : states.contains("positive_evidence") ? "positive_evidence" : compatible && states.allSatisfy({ $0 == "negative_evidence" }) ? "negative_evidence" : "unknown" }
            let shared = (common ?? []).sorted().map { $0.json }
            let supported: [JSON] = state == "positive_evidence" && op == "AND" ? shared : compatible || op == "OR" && !knownConflict ? children.filter { eq($0["state"], "positive_evidence") }.flatMap { points($0["supportedPositiveSamples"]) } : []
            return ["id": node["id"]!, "type": "group", "op": op, "state": state,
                    "scope": value(compatible ? scope : !knownConflict && op == "OR" ? knownScopes.first : nil), "reasons": reasons,
                    "partialCoverage": !compatible || children.contains { eq($0["state"], "unknown") || yes($0["partialCoverage"]) },
                    "sampleMembership": value(membership), "interpretation": "compound_supplied_predicates_only",
                    "predicateMeanings": unique(children.map { $0["predicateMeaning"] as? String ?? "compound" }), "pairing": pairingRaw,
                    "sharedPositiveSamples": shared, "supportedPositiveSamples": supported, "children": children,
                    "knownComponents": children.filter { member($0["state"], ["positive_evidence", "negative_evidence"]) }.map { $0["id"]! }]
        }
        return ["schema": "bpt.coaching-criteria.v1", "catalogVersion": "bpt.coaching-metrics.v1", "exercise": value(request["exercise"]), "variant": value(request["variant"]), "criterion": try visit(tree), "providedObservations": observations, "profileAuthority": "scoped_reference_only_not_whole_form_or_clinical_validation"]
    }
}

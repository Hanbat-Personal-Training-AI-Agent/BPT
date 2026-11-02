import Foundation
import CoreFoundation

/// Profile-free, bounded adapter for existing observation diagnostics. No I/O,
/// targets, training, delivery, geometry changes or implied source/model proof.
enum CoachingCriteriaBridge {
    typealias JSON = [String: Any]
    static let nativeMetricNames = ["leftKneeDeg", "rightKneeDeg", "leftHipDeg", "rightHipDeg", "leftElbowDeg", "rightElbowDeg", "leftUpperArmDeg", "rightUpperArmDeg", "trunkInclineDeg"]
    private static let null = NSNull()
    private static func value(_ x: Any?) -> Any { x ?? null }
    private static func finite(_ x: Any?) -> Double? {
        guard let n = x as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), let result = Double(n.stringValue), result.isFinite else { return nil }
        return result
    }
    private static func yes(_ x: Any?) -> Bool { guard let n = x as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }; return n.boolValue }
    private static func available(_ metric: JSON) -> Bool {
        if metric["available"] != nil { return yes(metric["available"]) }
        // Codable omits Metric.available because it is computed from value and reasons.
        return finite(metric["value"]) != nil && (metric["reasons"] as? [String])?.isEmpty == true
    }
    /// `source` preserves exact source PTS/rational/index/epoch; absent provenance is never filled.
    /// Input metric objects are retained by request(), while terminal summary keeps bounded fields only.
    static func request(metrics: JSON, source: JSON, context: JSON) throws -> JSON {
        guard let flush = context["flush_tail"] as? NSNumber, CFGetTypeID(flush) == CFBooleanGetTypeID() else { throw CoachingCriteria.ValidationError.invalid("explicit boolean flush required") }
        guard !metrics.isEmpty, metrics.count <= 32 else { throw CoachingCriteria.ValidationError.invalid("bridge metric budget") }
        let exerciseRaw = context["exercise"] as? String
        let aliases = ["row": "barbell-row", "barbell_row": "barbell-row"]
        let exercise = aliases[exerciseRaw ?? ""] ?? exerciseRaw
        let viewFlag = context["side_view"] as? NSNumber
        let viewKnown = viewFlag.map { CFGetTypeID($0) == CFBooleanGetTypeID() } ?? false
        let view = viewKnown && yes(context["side_view"]) ? "side" : "unknown"
        let epoch = (source["epoch"] as? String) ?? finite(source["epoch"]).map { String($0) }
        var observations: JSON = [:], children: [JSON] = []
        for name in metrics.keys.sorted() {
            guard name.utf8.count <= 128, let metric = metrics[name] as? JSON else { throw CoachingCriteria.ValidationError.invalid("malformed bridge metric") }
            let anatomicalSide = name.hasPrefix("left") ? "left" : name.hasPrefix("right") ? "right" : "bilateral"
            let contract = nativeMetricNames.contains(name) ? CoachingCriteria.metricContract(name) : nil
            let reasons = metric["reasons"] as? [String] ?? ["invalid_metric_reasons"]
            guard reasons.count <= 32, reasons.allSatisfy({ $0.utf8.count <= 128 }) else { throw CoachingCriteria.ValidationError.invalid("bridge reason budget") }
            var blocking = reasons
            if contract == nil { blocking.append("metric_not_mapped_by_native_bridge") }
            if yes(context["flush_tail"]) { blocking.append("flush_sample_not_observation") }
            let originalIdentity = source["sourceIdentity"] as? JSON ?? [:]
            let scope: JSON = ["sourceIdentity": ["inputSha256": value(originalIdentity["inputSha256"]), "sourceCommit": value(originalIdentity["sourceCommit"]), "modelSha256": value(originalIdentity["modelSha256"]), "epoch": value(epoch), "clockId": value(originalIdentity["clockId"])],
                               "timeBasis": value((source["time_basis"] as? String) == "sample_pts_seconds" ? "source_pts_seconds" : source["time_basis"]),
                               "startPts": value(source["source_pts"]), "endPts": value(source["source_pts"]),
                               "phase": value(context["phase"]), "side": anatomicalSide, "selectedSide": value(context["side"]), "view": view,
                               "coverageComplete": false, "expectedSourceIndices": [value(source["source_index"])]]
            observations[name] = ["metricId": name, "metricVersion": value(contract?["version"]), "definitionHash": value(contract?["definitionHash"]), "unit": value(contract?["unit"]), "coordinate": value(contract?["coordinate"]), "aggregation": "sample",
                                  "available": available(metric), "blockingReasons": blocking, "rawValue": value(metric["rawValue"]), "correctedValue": value(metric["value"]), "originalMetric": metric,
                                  "scope": scope, "samples": [["sourceIndex": value(source["source_index"]), "pts": value(source["source_pts"]), "value": value(metric["value"]), "rawValue": value(metric["rawValue"]), "available": available(metric), "blockingReasons": blocking, "side": anatomicalSide, "phase": value(context["phase"]), "view": view, "flush": yes(context["flush_tail"])]],
                                  "support": ["gravitySynchronized": yes(context["gravitySynchronized"])]]
            children.append(["type": "atom", "id": name, "observation": name])
        }
        return ["evaluation": ["mode": "causal", "asOfPts": value(source["source_pts"])], "exercise": value(exercise), "variant": "unconfirmed", "observations": observations, "profiles": JSON(), "criterion": ["type": "group", "id": "profile_free_native_coverage", "op": "OR", "children": children]]
    }
    static func failure(source: JSON, context: JSON, reason: String) -> JSON {
        let known = ["observation_encoding_failed", "criteria_evaluation_failed"]
        let sourceKeys = ["frame", "source_index", "source_pts", "source_time_value", "source_time_scale", "time_basis", "epoch"]
        let contextKeys = ["exercise", "phase", "side", "side_view", "source_kind", "flush_tail", "gravitySynchronized"]
        return ["schema": "bpt.coaching-criteria-terminal.v1", "status": "withheld_error", "errorReason": known.contains(reason) ? reason : "criteria_evaluation_failed", "catalogVersion": "bpt.coaching-metrics.v1", "state": "unknown", "profilesUsed": 0, "scope": "profile_free_observations_only", "profileAuthority": "scoped_reference_only_not_whole_form_or_clinical_validation", "source": Dictionary(uniqueKeysWithValues: sourceKeys.map { ($0, value(source[$0])) }), "context": Dictionary(uniqueKeysWithValues: contextKeys.map { ($0, value(context[$0])) }), "metrics": JSON(), "unmappedMetrics": [String](), "unsuppliedCatalogMetrics": (["cameraTorsoSignedDeg", "cameraHipLineDeviationRatio"] + nativeMetricNames).sorted()]
    }
    static func summary(metrics: JSON, source: JSON, context: JSON) throws -> JSON {
        let result = try CoachingCriteria.evaluate(request(metrics: metrics, source: source, context: context))
        let criterion = result["criterion"] as! JSON, decisions = criterion["children"] as! [JSON]
        var compact: JSON = [:]
        for decision in decisions {
            let name = decision["observationId"] as! String, metric = metrics[name] as! JSON
            compact[name] = ["rawValue": value(finite(metric["rawValue"])), "value": value(finite(metric["value"])), "available": available(metric), "reasons": metric["reasons"] as? [String] ?? ["invalid_metric_reasons"], "state": decision["state"]!, "criterionReasons": decision["reasons"]!, "interpretation": decision["interpretation"]!]
        }
        let sourceKeys = ["frame", "source_index", "source_pts", "source_time_value", "source_time_scale", "time_basis", "epoch"]
        let contextKeys = ["exercise", "phase", "side", "side_view", "source_kind", "flush_tail", "gravitySynchronized"]
        let summary: JSON = ["schema": "bpt.coaching-criteria-terminal.v1", "status": "observed", "catalogVersion": result["catalogVersion"]!, "state": criterion["state"]!, "profilesUsed": 0,
                             "scope": "profile_free_observations_only", "profileAuthority": result["profileAuthority"]!,
                             "source": Dictionary(uniqueKeysWithValues: sourceKeys.map { ($0, value(source[$0])) }), "context": Dictionary(uniqueKeysWithValues: contextKeys.map { ($0, value(context[$0])) }),
                             "metrics": compact, "unmappedMetrics": metrics.keys.filter { !nativeMetricNames.contains($0) }.sorted(),
                             "unsuppliedCatalogMetrics": (["cameraTorsoSignedDeg", "cameraHipLineDeviationRatio"] + nativeMetricNames).filter { metrics[$0] == nil }.sorted()]
        // Enforce bounded terminal payload independently of arbitrary input metadata.
        guard try JSONSerialization.data(withJSONObject: summary).count <= 32_768 else { throw CoachingCriteria.ValidationError.invalid("bridge payload budget") }
        return summary
    }
}

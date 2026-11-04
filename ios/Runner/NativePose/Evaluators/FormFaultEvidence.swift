import Foundation

/// Original source identity supplied by the caller, never reconstructed from a frame counter.
struct FormFaultSource {
    let frame: Int
    let sourceIndex: Int?
    let timeValue: Int64?
    let timeScale: Int32?
    let timeEpoch: Int64
    let timeFlags: UInt32
    let session: String
    let kind: String
    let flush: Bool
    init(frame: Int, sourceIndex: Int?, timeValue: Int64?, timeScale: Int32?, session: String,
         kind: String, flush: Bool, timeEpoch: Int64 = 0, timeFlags: UInt32 = 1) {
        self.frame = frame; self.sourceIndex = sourceIndex; self.timeValue = timeValue; self.timeScale = timeScale
        self.session = session; self.kind = kind; self.flush = flush; self.timeEpoch = timeEpoch; self.timeFlags = timeFlags
    }
    var key: String { sourceIndex.map { "\(session)/source/\($0)" } ?? "\(session)/frame/\(frame)" }
    var seconds: Double? {
        guard timeFlags & 1 != 0, timeFlags & 28 == 0,
              let value = timeValue, let scale = timeScale, scale > 0 else { return nil }
        let result = Double(value) / Double(scale)
        return result.isFinite ? result : nil
    }
    var dictionary: [String: Any] {
        ["frame": frame, "sourceIndex": sourceIndex as Any? ?? NSNull(),
         "timeValue": timeValue as Any? ?? NSNull(), "timeScale": timeScale as Any? ?? NSNull(),
         "timeEpoch": timeEpoch, "timeFlags": timeFlags,
         "seconds": seconds as Any? ?? NSNull(), "session": session, "kind": kind,
         "flush": flush, "sourceKey": key]
    }
}

enum FormFaultJSON {
    static func number(_ value: Double?) -> Any { value.flatMap { $0.isFinite ? $0 : nil } as Any? ?? NSNull() }
    static func optional(_ value: Bool?) -> Any { value as Any? ?? NSNull() }
    static func values(_ values: [String: Double]) -> [String: Any] { values.mapValues { number($0) } }
    static func config<T>(_ config: T) -> [String: Any] {
        var result: [String: Any] = [:]
        for item in Mirror(reflecting: config).children {
            guard let name = item.label else { continue }
            if let set = item.value as? Set<String> { result[name] = set.sorted() }
            else if let value = item.value as? Bool { result[name] = value }
            else if let value = item.value as? Int { result[name] = value }
            else if let value = item.value as? Double { result[name] = number(value) }
        }
        return result
    }
}

/// Comparison-only stream. Record callbacks run synchronously on the evaluator's owner queue.
/// A completed writer is not evidence of full source coverage without an expected input manifest.
final class FormFaultEvidence {
    let runID: String
    let url: URL?
    private let callback: ([String: Any]) throws -> Void
    private let closeOutput: () -> Void
    private let maximumRecords: Int
    private let maximumBytes: Int
    private var sequence = 0
    private var bytes = 0
    private var closed = false
    private var failure: String?
    private var expected: [String: FormFaultSource]?
    private var observed = Set<String>()
    private var duplicateSources = 0
    private var unknownSources = 0
    private var mismatchedSources = 0
    private var failedSources = Set<String>()
    private var frameRecords = 0
    private var repRecords = 0
    private var attemptedRecords = 0
    private var writtenFrames = 0
    private var writtenReps = 0

    init(runID: String, binding: [String: Any] = [:], expectedSources: [FormFaultSource]? = nil,
         maximumRecords: Int = 20_000, maximumBytes: Int = 32 * 1024 * 1024,
         url: URL? = nil, onClose: @escaping () -> Void = {},
         onRecord: @escaping ([String: Any]) throws -> Void) {
        self.runID = runID; self.url = url; callback = onRecord; closeOutput = onClose
        self.maximumRecords = max(2, maximumRecords); self.maximumBytes = max(4096, maximumBytes)
        if let sources = expectedSources {
            expected = [:]
            for source in sources {
                if expected?.updateValue(source, forKey: source.key) != nil { failure = "duplicate_expected_source" }
            }
        }
        emit("header", ["binding": binding,
            "scope": "source_rule_trace_not_import_decisions",
            "expectedSourceScope": expected == nil ? "observed_judgements_only" : "declared_input_manifest",
            "expectedSources": expected?.count as Any? ?? NSNull(),
            "expectedSourceManifest": expectedSources?.map { $0.dictionary } as Any? ?? NSNull(),
            "maximumRecords": self.maximumRecords, "maximumBytes": self.maximumBytes])
    }

    static func file(directory: URL, runID: String, binding: [String: Any] = [:],
                     expectedSources: [FormFaultSource]? = nil) throws -> FormFaultEvidence {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fault_\(UUID().uuidString).jsonl")
        try Data().write(to: url, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: url)
        var written: UInt64 = 0
        return FormFaultEvidence(runID: runID, binding: binding, expectedSources: expectedSources, url: url, onClose: { try? handle.close() }) { record in
            let data = try JSONSerialization.data(withJSONObject: record, options: .sortedKeys)
            do { try handle.write(contentsOf: data + Data([10])); written += UInt64(data.count + 1) }
            catch { try? handle.truncate(atOffset: written); try? handle.seek(toOffset: written); throw error }
        }
    }

    private func emit(_ type: String, _ fields: [String: Any]) {
        guard !closed else { return }
        attemptedRecords += 1
        let record = fields.merging(["contract": "bpt-native-fault-trace-v1", "type": type,
                                     "sequence": sequence, "runID": runID]) { _, reserved in reserved }
        do {
            let data = try JSONSerialization.data(withJSONObject: record, options: .sortedKeys)
            guard sequence < maximumRecords - 1, bytes + data.count + 1 <= maximumBytes - 2048 else {
                failure = "capture_limit"; finish(reason: "capture_limit", sourceDrained: false); return
            }
            try callback(record); sequence += 1; bytes += data.count + 1
            if type == "frame" { writtenFrames += 1 }
            if type == "rep" { writtenReps += 1 }
        } catch { failure = "capture_write_or_serialization_failed"; finish(reason: failure!, sourceDrained: false) }
    }

    func frame(_ record: [String: Any], source: FormFaultSource?) {
        guard !closed else { return }
        frameRecords += 1
        if let source {
            if !observed.insert(source.key).inserted { duplicateSources += 1 }
            if source.seconds == nil { unknownSources += 1 }
            if let expected, let wanted = expected[source.key] {
                if wanted.frame != source.frame || wanted.sourceIndex != source.sourceIndex || wanted.timeValue != source.timeValue ||
                    wanted.timeScale != source.timeScale || wanted.kind != source.kind ||
                    wanted.timeEpoch != source.timeEpoch || wanted.timeFlags != source.timeFlags {
                    mismatchedSources += 1
                }
            } else if expected != nil { mismatchedSources += 1 }
        } else { unknownSources += 1 }
        emit("frame", record.merging(["source": source?.dictionary as Any? ?? NSNull()]) { _, value in value })
    }

    func ingressFailure(source: FormFaultSource, reason: String) {
        guard !closed else { return }; failedSources.insert(source.key)
        emit("ingress_failure", ["source": source.dictionary, "reason": reason])
    }

    func rep(_ record: [String: Any]) { guard !closed else { return }; repRecords += 1; emit("rep", record) }
    func reset() { emit("reset", ["reason": "tracker_reset"]) }
    func finish(reason: String, sourceDrained: Bool) {
        guard !closed else { return }; closed = true
        let missing = expected.map { Set($0.keys).subtracting(observed).count }
        let coverage = expected != nil && missing == 0 && unknownSources == 0 &&
            duplicateSources == 0 && mismatchedSources == 0 && failedSources.isEmpty && failure == nil && sourceDrained
        let footer: [String: Any] = ["contract": "bpt-native-fault-trace-v1", "type": "footer",
            "sequence": sequence, "runID": runID, "reason": reason,
            "writerComplete": sourceDrained && failure == nil, "sourceDrained": sourceDrained,
            "sourceCoverageComplete": coverage, "failure": failure as Any? ?? NSNull(),
            "recordsBeforeFooter": sequence, "bytesBeforeFooter": bytes,
            "attemptedRecords": attemptedRecords,
            "frameRecordsAttempted": frameRecords, "repRecordsAttempted": repRecords,
            "frameRecordsWritten": writtenFrames, "repRecordsWritten": writtenReps,
            "expectedSources": expected?.count as Any? ?? NSNull(), "observedSources": observed.count,
            "missingSources": missing as Any? ?? NSNull(), "unknownSources": unknownSources,
            "duplicateSources": duplicateSources, "mismatchedSources": mismatchedSources,
            "failedSourcesCount": failedSources.count]
        if let encoded = try? JSONSerialization.data(withJSONObject: footer, options: .sortedKeys),
           encoded.count + 1 <= 2048, bytes + encoded.count + 1 <= maximumBytes {
            try? callback(footer)
        }
        closeOutput()
    }
    deinit { finish(reason: "deinitialized", sourceDrained: false) }
}

struct FormFaultHistory {
    let traceID: String?
    let repIndex: Int?
    let metrics: [String: Double]
    var dictionary: [String: Any] {
        ["traceID": traceID as Any? ?? NSNull(), "repIndex": repIndex as Any? ?? NSNull(),
         "metrics": FormFaultJSON.values(metrics)]
    }
}

/// Lineage only: these methods observe the aggregator's working values and selections.
final class FormFaultAggregation {
    let frames: [FormFrameSample]
    private(set) var metrics: [String: [String: Any]] = [:]
    init(frames: [FormFrameSample]) { self.frames = frames }
    func put(_ name: String, value: Double?) {
        let field: String
        switch name {
        case "elbow_min", "elbow_max": field = "elbow"
        case "knee_min", "knee_max": field = "knee"
        case "hip_angle_max": field = "hipAngle"
        case "torso_min", "torso_max", "torso_mean", "torso_at_bottom", "hips_first_torso_rise": field = "torso"
        case "hip_dev_min", "hip_dev_max": field = "hipDeviation"
        case "head_dev_change_min", "head_dev_change_max": field = "headDeviation"
        case "elbow_behind_max": field = "elbowBehind"
        case "knee_ankle_gap_ratio_min": field = "kneeAnkleGapRatio"
        case "heel_rise_max": field = "heelToe"
        case "ear_shoulder_drop": field = "earShoulder"
        case "first_rep_top_wrist_ahead": field = "wristAhead"
        default: field = name
        }
        let contributors = frames.filter { $0.faultMeasurements[field] != nil }.map(\.frame)
        metrics[name] = ["value": FormFaultJSON.number(value), "finite": value?.isFinite ?? false,
                         "field": field, "scopeFrames": frames.map(\.frame), "contributingFrames": contributors,
                         "selectedFrames": [], "referenceFrames": [], "selection": "all_available_field_values"]
        if let value, value.isFinite, name.hasSuffix("_min") || name.hasSuffix("_max") {
            metrics[name]?["selectedFrames"] = frames.filter { $0.faultMeasurements[field] == value }.map(\.frame)
        }
        if name.hasPrefix("head_dev_change") || name == "heel_rise_max" {
            metrics[name]?["referenceFrames"] = contributors.first.map { [$0] } ?? []
            metrics[name]?["referenceKind"] = "first_available_not_asserted_rep_start"
        }
        if name == "front_view_fraction" {
            metrics[name]?["field"] = "frontView"
            metrics[name]?["contributingFrames"] = frames.filter { $0.frontView != nil }.map(\.frame)
        }
    }
    func stage(_ name: String, operation: String, fields: [String], scope: [Int], selected: [Int]) {
        var stages = metrics[name]?["selectionStages"] as? [[String:Any]] ?? []
        stages.append(["operation":operation,"fields":fields,"scopeFrames":scope,"selectedFrames":selected])
        metrics[name]?["selectionStages"] = stages
    }
    func selection(_ name: String, selected: [Int] = [], reference: [Int] = [], scope: [Int]? = nil,
                   fields: [String], operation: String, contributors: [Int]? = nil,
                   selectorFields: [String] = [], selectorFrames: [Int] = []) {
        metrics[name]?["selectedFrames"] = selected; metrics[name]?["referenceFrames"] = reference
        if let scope { metrics[name]?["scopeFrames"] = scope }
        let selectedScope = Set(scope ?? frames.map(\.frame))
        let byField = Dictionary(uniqueKeysWithValues: fields.map { field in
            (field, frames.filter { selectedScope.contains($0.frame) && $0.faultMeasurements[field] != nil }.map(\.frame))
        })
        metrics[name]?["contributorsByField"] = byField
        metrics[name]?["contributingFrames"] = contributors ?? Array(Set(byField.values.flatMap { $0 })).sorted()
        metrics[name]?["dependencyFields"] = fields; metrics[name]?["selection"] = operation
        metrics[name]?["selectorFields"] = selectorFields; metrics[name]?["selectorFrames"] = selectorFrames
    }
}

extension FormFrameSample {
    var faultMeasurements: [String: Double] {
        let fields: [(String, Double?)] = [("elbow",elbow),("knee",knee),("hipAngle",hipAngle),("torso",torso),
            ("hipDeviation",hipDeviation),("headDeviation",headDeviation),("headAngle",headAngle),
            ("wristAhead",wristAhead),("elbowBehind",elbowBehind),("earShoulder",earShoulder),
            ("hipY",hipY),("shoulderY",shoulderY),("torsoLength",torsoLength),
            ("shoulderRatio",shoulderRatio),("kneeAnkleGapRatio",kneeAnkleGapRatio),("heelToe",heelToe)]
        return Dictionary(uniqueKeysWithValues: fields.compactMap { name,value in value.map { (name,$0) } })
    }
    var faultDictionary: [String: Any] {
        ["frame":frame,"phase":phase,"side":side.rawValue,"requiredOK":requiredOK,
         "measurements":FormFaultJSON.values(faultMeasurements),
         "nonfiniteMeasurements":faultMeasurements.filter { !$0.value.isFinite }.keys.sorted(),
         "frontView":FormFaultJSON.optional(frontView),"state3D":state3D?.rawValue as Any? ?? NSNull(),
         "has3D":has3D,"bad3D":bad3D,"inputSupport":faultInputSupport as Any? ?? NSNull(),
         "source":faultSource?.dictionary as Any? ?? NSNull()]
    }
}

/// Exact condition/operand observations, separate from delivery qualification and export eligibility.
final class FormFaultJudge {
    let traceID: String
    private let source: String
    private let repIndex: Int
    private let metrics: [String: Double]
    private let aggregation: FormFaultAggregation
    private let history: [FormFaultHistory]
    private var entries: [String: [String: Any]] = [:]
    private var operands: [String: [[String: Any]]] = [:]
    private var support: [String: [(positive: Bool, negative: Bool)]] = [:]
    private var active: String?
    private var view: [String: Any] = [:]

    init(traceID: String, source: String, repIndex: Int, exercise: FormExercise, metrics: [String: Double],
         aggregation: FormFaultAggregation, history: [FormFaultHistory],
         common: FormCommonConfig, squat: SquatFormConfig, row: BarbellRowFormConfig) {
        self.traceID = traceID; self.source = source; self.repIndex = repIndex; self.metrics = metrics
        self.aggregation = aggregation; self.history = history
        let prefix: String
        switch exercise { case .pushUp: prefix = "pushup_"; case .squat: prefix = "squat_"; case .barbellRow: prefix = "row_"; default: prefix = "unsupported_" }
        for item in FormWarningTracker.rules[exercise] ?? [] where item.key.hasPrefix(prefix) {
            let enabled = item.key == "squat_heel_rise" ? squat.heelRiseEnabled : item.key == "row_shrug" ? row.shrugEnabled : true
            entries[item.key] = ["rule":item.key,"executionEnabled":enabled,
                "deliveryEnabled":common.enabledFeedbackKeys.contains(item.key),"callState":"not_called",
                "condition":NSNull(),"rawFired":false,"deliveryAssessed":false,
                "positiveOperandEvidence":NSNull(),"negativeOperandEvidence":NSNull()]
        }
    }
    func begin(_ key: String) { active = entries[key] == nil ? nil : key }
    func setView(actualSideView: Bool, qualified: Bool, sessionSideView: Bool?, fraction: Double?) {
        view = ["actualSideView":actualSideView,"qualified":qualified,
                "sessionSideView":FormFaultJSON.optional(sessionSideView),"frontViewFraction":FormFaultJSON.number(fraction)]
    }
    func complete(_ key: String, condition: Bool?) {
        guard entries[key] != nil else { active = nil; return }
        entries[key]?["condition"] = FormFaultJSON.optional(condition)
        entries[key]?["callState"] = condition.map { $0 ? "true" : "false" } ?? "nil"
        let proofs = support[key] ?? []
        if key == "squat_no_lockout" {
            entries[key]?["positiveOperandEvidence"] = condition == true && proofs.contains { $0.positive }
            entries[key]?["negativeOperandEvidence"] = condition == false && proofs.count == 2 && proofs.allSatisfy { $0.negative }
        } else if !proofs.isEmpty {
            entries[key]?["positiveOperandEvidence"] = condition == true && proofs.allSatisfy { $0.positive }
            entries[key]?["negativeOperandEvidence"] = condition == false && proofs.allSatisfy { $0.negative }
        }
        active = nil
    }
    func operand(operation: String, metric: String, current: Double?, threshold: Double?, result: Bool?,
                 reference: Double? = nil, indices: [Int] = [], expectedCount: Int? = nil,
                 completeReference: Bool = true, currentIncluded: Bool = false, derivedCurrent: Double? = nil) {
        guard let key = active else { return }
        record(key, operation:operation, metric:metric, current:current, threshold:threshold, result:result,
               reference:reference, indices:indices, expectedCount:expectedCount,
               completeReference:completeReference,currentIncluded:currentIncluded,derivedCurrent:derivedCurrent)
    }
    func record(_ key: String, operation: String, metric: String, current: Double?, threshold: Double?, result: Bool?,
                reference: Double? = nil, indices: [Int] = [], expectedCount: Int? = nil,
                completeReference: Bool = true, currentIncluded: Bool = false, derivedCurrent: Double? = nil) {
        guard entries[key] != nil else { return }
        let refs: [[String: Any]] = indices.map { index in
            if history.indices.contains(index) {
                return ["index":index,"traceID":history[index].traceID as Any? ?? NSNull(),
                        "repIndex":history[index].repIndex as Any? ?? NSNull(),"value":FormFaultJSON.number(history[index].metrics[metric])]
            }
            return ["index":index,"traceID":traceID,"repIndex":repIndex,"value":FormFaultJSON.number(current)]
        }
        let finiteCurrent = (derivedCurrent ?? current)?.isFinite == true
        let consumedFinite = indices.allSatisfy { index in
            history.indices.contains(index) ? history[index].metrics[metric].map(\.isFinite) ?? true : finiteCurrent
        }
        let finiteReference = reference == nil ? indices.isEmpty : reference?.isFinite == true
        let thresholdRequired = ["over","under","over_baseline","below_set_max","trend"].contains(operation)
        let finiteThreshold = threshold?.isFinite ?? !thresholdRequired
        let positive = result == true && finiteCurrent && consumedFinite && finiteReference && finiteThreshold &&
            (operation == "below_set_max" || completeReference)
        let negative = result == false && finiteCurrent && consumedFinite && finiteReference && finiteThreshold && completeReference
        operands[key,default:[]].append(["operation":operation,"metric":metric,
            "currentValue":FormFaultJSON.number(current),"derivedCurrentValue":FormFaultJSON.number(derivedCurrent),"threshold":FormFaultJSON.number(threshold),
            "result":FormFaultJSON.optional(result),"referenceValue":FormFaultJSON.number(reference),
            "referenceEntries":refs,"expectedReferenceCount":expectedCount as Any? ?? NSNull(),
            "currentIncluded":currentIncluded,"finiteCurrent":finiteCurrent,"finiteThreshold":finiteThreshold,"completeReference":completeReference,
            "positiveOperandEvidence":positive,"negativeOperandEvidence":negative])
        support[key,default:[]].append((positive,negative))
    }
    func manual(_ key: String, inputs: [String: Double], condition: Bool?, operation: String,
                referenceMetric: String? = nil, referenceValue: Double? = nil, indices: [Int] = [], expectedCount: Int? = nil,
                thresholds: [String: Double] = [:]) {
        guard entries[key] != nil else { return }
        entries[key]?["manualInputs"] = FormFaultJSON.values(inputs)
        entries[key]?["manualOperation"] = operation
        entries[key]?["manualThresholds"] = FormFaultJSON.values(thresholds)
        let finite = inputs.values.allSatisfy(\.isFinite) && thresholds.values.allSatisfy(\.isFinite)
        let complete = indices.count == (expectedCount ?? indices.count) && indices.allSatisfy { i in
            history.indices.contains(i) && referenceMetric.map { history[i].metrics[$0]?.isFinite == true } != false
        }
        let good = finite && complete && (referenceValue == nil || referenceValue?.isFinite == true)
        support[key,default:[]].append((condition == true && good,condition == false && good))
        if let metric = referenceMetric {
            let previous = active; active = key
            operand(operation:operation,metric:metric,current:inputs[metric],threshold:nil,result:condition,
                    reference:referenceValue,indices:indices,expectedCount:expectedCount,completeReference:complete)
            active = previous
        }
    }
    func finish(fired: [String], assessed: Set<String>) -> [String: Any] {
        let rules = entries.keys.sorted().map { key -> [String:Any] in
            var row = entries[key]!
            row["rawFired"] = fired.contains(key); row["deliveryAssessed"] = assessed.contains(key)
            row["operands"] = operands[key] ?? []
            if row["callState"] as? String == "not_called" {
                row["notCalledReason"] = row["executionEnabled"] as? Bool == false ? "rule_disabled" :
                    (view["actualSideView"] as? Bool == false ? "view_branch" : "source_condition_not_available_or_not_applicable")
            }
            return row
        }
        return ["traceID":traceID,"source":source,"metrics":FormFaultJSON.values(metrics),
                "metricSupport":aggregation.metrics,"history":history.map(\.dictionary),"view":view,"rules":rules]
    }
}

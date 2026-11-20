import Foundation

/// Independent, opt-in terminal-window experiment. Never edits native reports or emits feedback.
/// An observed stable top window is not full anatomical extension or a correct-form label.
struct TerminalObservationCandidate {
    struct Config: Codable, Equatable {
        // Untuned experimental observation parameters, not clinical/form thresholds.
        var stableSeconds = 0.25
        var minimumSamples = 5
        var maximumAngularSpeed = 10.0
        var maximumSourceGap = 0.15
        var timeoutSeconds = 1.5
        var minimumReferences = 3
        var valid: Bool {
            stableSeconds.isFinite && stableSeconds > 0 && minimumSamples >= 2 && minimumSamples <= 100 &&
            maximumAngularSpeed.isFinite && maximumAngularSpeed >= 0 && maximumSourceGap.isFinite && maximumSourceGap > 0 &&
            timeoutSeconds.isFinite && timeoutSeconds > stableSeconds && minimumReferences > 0 && minimumReferences <= 100
        }
    }
    struct Original: Codable, Equatable {
        var epoch: Int
        var exercise: String
        var rep: Int
        var startFrame: Int
        var endFrame: Int
        var side: String
        var threshold: Double
        var originalMaxima: [String: Double]
        var metrics: [String] { exercise == "squat" ? ["knee", "hip"] : ["elbow"] }
    }
    struct Begin: Codable {
        var original: Original
        var hostTime: Double
    }
    struct Frame: Codable {
        var epoch: Int
        var frame: Int
        var sourceIndex: Int?
        var sourceTime: Double?
        var hostTime: Double
        var activeRepStart: Int?
        var side: String?
        var phase: String?
        var required2D: Bool
        var sideView: Bool?
        var state: String
        var flushed: Bool
        var setEndFlushTail = false
        var coordinateKey: String
        var assessmentAngles: [String: Double]
        var rawAngles: [String: Double]
    }
    struct Report: Encodable, Equatable {
        var original: Original
        var closure: String
        var assessment: String
        var reasons: [String]
        var coverage: String
        var observedFrames: Int
        var topFrames: Int
        var firstSourceTime: Double?
        var lastSourceTime: Double?
        var stableSeconds: Double
        var observedTopMaxima: [String: Double]
        var allFollowupMaxima: [String: Double]
        var rawFollowupMaxima: [String: Double]
        var terminalPlateauMaxima: [String: Double]
        var referencePlateauMaxima: [String: Double]
        var relativeDeficits: [String: Double]
        var referenceCount: Int
        let scope = "same_protocol_past_terminal_windows_self_relative_not_full_extension"
    }
    private struct Pending {
        var original: Original
        var beganHost: Double
        var lastFrame: Frame?
        var coordinateKey: String?
        var endTime: Double?
        var firstTime: Double?
        var observedFrames = 0
        var topFrames = 0
        var maxima: [String: Double] = [:]
        var plateauMaxima: [String: Double] = [:]
        var allFollowupMaxima: [String: Double] = [:]
        var rawFollowupMaxima: [String: Double] = [:]
        var lastTopAngles: [String: Double]?
        var plateauStart: Double?
        var plateauSamples = 0
        var stableDuration = 0.0
        var stable = false
    }
    let config: Config
    private(set) var epoch: Int?
    private(set) var rejectedStaleFrames = 0
    private var pending: Pending?
    private var history: [String: [[String: Double]]] = [:]
    private var historyCoordinateKey: String?
    private var reports: [Report] = []
    var pendingRep: Int? { pending?.original.rep }

    init(config: Config = .init()) { self.config = config }

    mutating func start(epoch: Int) {
        if pending != nil { close("reset", invalid: "reset") }
        self.epoch = epoch
        history = [:]
        historyCoordinateKey = nil
    }
    mutating func begin(_ original: Original, hostTime: Double) {
        guard config.valid, ["squat", "pushUp", "pushup"].contains(original.exercise),
              ["left", "right"].contains(original.side), original.startFrame >= 0, original.endFrame >= original.startFrame,
              original.threshold.isFinite, original.threshold >= 0, hostTime.isFinite else { return }
        guard epoch == original.epoch else {
            reports.append(.init(original: original, closure: "inactive_epoch", assessment: "withheld", reasons: ["inactive_epoch"],
                coverage: "incomplete_terminal_observation", observedFrames: 0, topFrames: 0, firstSourceTime: nil, lastSourceTime: nil,
                stableSeconds: 0, observedTopMaxima: [:], allFollowupMaxima: [:], rawFollowupMaxima: [:], terminalPlateauMaxima: [:], referencePlateauMaxima: [:], relativeDeficits: [:], referenceCount: 0))
            if reports.count > 100 { reports.removeFirst() }
            return
        }
        if pending != nil { close("superseded_report", invalid: "missing_next_begin_evidence") }
        pending = Pending(original: original, beganHost: hostTime)
    }
    mutating func observe(_ frame: Frame) {
        guard frame.epoch == epoch else { rejectedStaleFrames += 1; return }
        if pending == nil {
            if frame.state == "tracking_lost" || (frame.flushed && !frame.setEndFlushTail) || (historyCoordinateKey != nil && historyCoordinateKey != frame.coordinateKey) {
                history = [:]; historyCoordinateKey = nil
            }
            return
        }
        guard var p = pending else { return }
        let previousSourceTime = p.lastFrame?.sourceTime
        guard frame.epoch == p.original.epoch else { rejectedStaleFrames += 1; return }
        if frame.setEndFlushTail { return } // genuine pre-end deliveries may still be pending; clamped tail is not evidence
        guard frame.hostTime.isFinite, frame.hostTime >= p.beganHost else { close("invalid_clock", invalid: "host_clock"); return }
        if frame.hostTime - p.beganHost >= config.timeoutSeconds { close("timeout", invalid: "timeout"); return }
        guard let time = frame.sourceTime, time.isFinite, time >= 0, let source = frame.sourceIndex, source >= 0 else {
            close("invalid_clock", invalid: "missing_source_clock"); return
        }
        guard frame.frame >= p.original.endFrame else { return } // earlier source is not follow-up
        if let previous = p.lastFrame {
            guard let t = previous.sourceTime, let index = previous.sourceIndex,
                  time > t, source > index, frame.frame > previous.frame else { close("invalid_clock", invalid: "duplicate_or_regressing_source"); return }
            if time - t > config.maximumSourceGap + 1e-9 { close("source_gap", invalid: "source_gap"); return }
        }
        // Validate clocks/deadline first, but close before consuming the next rep's geometry/support.
        if let began = frame.activeRepStart, began > p.original.startFrame {
            close("next_rep_started"); return
        }
        if p.lastFrame == nil, historyCoordinateKey != frame.coordinateKey {
            history = [:]
            historyCoordinateKey = frame.coordinateKey
        }
        if let coordinate = p.coordinateKey, coordinate != frame.coordinateKey { close("coordinate_reset", invalid: "coordinate_changed"); return }
        p.coordinateKey = frame.coordinateKey
        p.lastFrame = frame
        if frame.flushed { pending = p; close("lifter_flush", invalid: "clamped_or_reset_flush"); history = [:]; historyCoordinateKey = nil; return }
        if frame.frame == p.original.endFrame {
            p.endTime = time
            pending = p
            return // original interval's last frame is not a new terminal observation
        }
        guard let ended = p.endTime else { close("missing_anchor", invalid: "missing_original_end_source"); return }
        if time - ended >= config.timeoutSeconds { close("timeout", invalid: "timeout"); return }
        for metric in p.original.metrics {
            if let v = frame.assessmentAngles[metric], v.isFinite { p.allFollowupMaxima[metric] = max(p.allFollowupMaxima[metric] ?? v, v) }
            if let v = frame.rawAngles[metric], v.isFinite { p.rawFollowupMaxima[metric] = max(p.rawFollowupMaxima[metric] ?? v, v) }
        }
        pending = p // retain diagnostic maxima even when this source invalidates eligibility
        guard frame.side == p.original.side else { close("side_changed", invalid: "side_changed"); return }
        guard ["ok", "partial_3d"].contains(frame.state), frame.required2D, frame.sideView == true else {
            close("support_lost", invalid: "missing_native_assessment_or_view_support")
            if frame.state == "tracking_lost" { history = [:]; historyCoordinateKey = nil }
            return
        }
        guard p.original.metrics.allSatisfy({ frame.assessmentAngles[$0]?.isFinite == true }) else {
            close("invalid_geometry", invalid: "missing_dependent_angle"); return
        }
        guard let phase = frame.phase, phase != "unknown", !phase.isEmpty else { close("unknown_phase", invalid: "unknown_phase"); return }
        if phase != "top" {
            if p.topFrames > 0 { pending = p; close("top_phase_exited"); return }
            p.observedFrames += 1
            pending = p
            return // awaiting top; no phase/GT interpolation
        }
        p.observedFrames += 1
        p.topFrames += 1
        p.firstTime = p.firstTime ?? time
        let angles = Dictionary(uniqueKeysWithValues: p.original.metrics.map { ($0, frame.assessmentAngles[$0]!) })
        for (key, value) in angles { p.maxima[key] = max(p.maxima[key] ?? value, value) }
        if let previousAngles = p.lastTopAngles, let previous = previousSourceTime,
           angles.allSatisfy({ abs($0.value - previousAngles[$0.key]!) / (time - previous) <= config.maximumAngularSpeed + 1e-9 }) {
            p.plateauSamples += 1
        } else {
            p.plateauStart = time
            p.plateauSamples = 1
            p.plateauMaxima = [:]
            p.stable = false
        }
        for (key, value) in angles { p.plateauMaxima[key] = max(p.plateauMaxima[key] ?? value, value) }
        p.lastTopAngles = angles
        p.stableDuration = time - (p.plateauStart ?? time)
        p.stable = p.plateauSamples >= config.minimumSamples && p.stableDuration + 1e-9 >= config.stableSeconds
        pending = p
        // Stability is provisional; keep collecting later extension until an actual causal boundary.
    }
    mutating func expire(epoch: Int, rep: Int, hostTime: Double) {
        guard let p = pending, p.original.epoch == epoch, p.original.rep == rep,
              hostTime.isFinite, hostTime - p.beganHost >= config.timeoutSeconds else { return }
        close("watchdog_timeout", invalid: "timeout_without_new_source")
    }
    mutating func end(epoch: Int, reason: String, hostTime: Double? = nil) {
        guard self.epoch == epoch else { return } // stale end callback cannot close a new set
        if let p = pending {
            if reason == "set_end" {
                if let hostTime, hostTime.isFinite, hostTime >= p.beganHost, hostTime - p.beganHost < config.timeoutSeconds {
                    close(reason)
                } else {
                    close(reason, invalid: "set_end_without_fresh_operational_deadline")
                }
            } else { close(reason, invalid: reason) }
        }
        self.epoch = nil
        history = [:]
    }
    private mutating func close(_ reason: String, invalid: String? = nil) {
        guard let p = pending else { return }
        pending = nil
        let transientHigher = p.original.metrics.contains { metric in
            guard let high = p.allFollowupMaxima[metric], let settled = p.plateauMaxima[metric] else { return false }
            return high - settled > p.original.threshold
        }
        let ambiguous = invalid == nil && p.stable && transientHigher
        let covered = invalid == nil && !ambiguous && p.stable && p.topFrames >= config.minimumSamples
        let key = p.original.exercise + "/" + p.original.side
        let past = history[key, default: []]
        let reference = Dictionary(uniqueKeysWithValues: p.original.metrics.compactMap { metric in
            past.compactMap { $0[metric] }.max().map { (metric, $0) }
        })
        let comparable = covered && past.count >= config.minimumReferences && reference.count == p.original.metrics.count
        let deficits = comparable ? Dictionary(uniqueKeysWithValues: p.original.metrics.map { ($0, max(0, reference[$0]! - p.plateauMaxima[$0]!)) }) : [:]
        let reasons = invalid.map { [$0] } ?? (ambiguous ? ["transient_higher_extension_outside_last_plateau"] : !covered ? ["terminal_top_not_continuously_observed_stable"] : !comparable ? ["requires_same_protocol_past_reference"] : [])
        let assessment = comparable ? (deficits.values.contains { $0 > p.original.threshold } ? "relative_terminal_deficit_observed" : "relative_deficit_not_observed") : "withheld"
        reports.append(.init(original: p.original, closure: reason, assessment: assessment, reasons: reasons,
            coverage: covered ? "observed_stable_top_window" : ambiguous ? "ambiguous_terminal_observation" : "incomplete_terminal_observation",
            observedFrames: p.observedFrames, topFrames: p.topFrames, firstSourceTime: p.firstTime,
            lastSourceTime: p.lastFrame?.sourceTime, stableSeconds: p.stableDuration,
            observedTopMaxima: p.maxima, allFollowupMaxima: p.allFollowupMaxima, rawFollowupMaxima: p.rawFollowupMaxima, terminalPlateauMaxima: p.plateauMaxima, referencePlateauMaxima: reference, relativeDeficits: deficits, referenceCount: past.count))
        if reports.count > 100 { reports.removeFirst() }
        if covered {
            history[key, default: []].append(p.plateauMaxima)
            if history[key]!.count > 100 { history[key]!.removeFirst() }
        }
    }
    mutating func drain() -> [Report] {
        defer { reports.removeAll(keepingCapacity: true) }
        return reports
    }
}

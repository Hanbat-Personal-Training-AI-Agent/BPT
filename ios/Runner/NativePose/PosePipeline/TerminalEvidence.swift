import Foundation

/// Numeric-only, opt-in diagnostics. This lease never gates or changes the evaluator.
final class TerminalEvidenceCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    private var active = false
    private var closing = false
    private var inFlight: Set<Int> = []
    private var abandoned = false
    func begin() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1; active = true; closing = false
        inFlight = []; abandoned = false
        return generation
    }
    func snapshot() -> Int? {
        lock.lock(); defer { lock.unlock() }
        return active && !closing ? generation : nil
    }
    func capture(frame: Int) -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard active && !closing else { return nil }
        guard inFlight.count < 6000 else { abandoned = true; return nil }
        inFlight.insert(frame)
        return generation
    }
    func delivered(epoch: Int?, frame: Int, failed: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        guard active, epoch == generation, inFlight.remove(frame) != nil else { return }
        abandoned = abandoned || failed
    }
    func drainStatus(_ expected: Int) -> (pending: Int, failed: Bool)? {
        lock.lock(); defer { lock.unlock() }
        guard active, generation == expected else { return nil }
        return (inFlight.count, abandoned)
    }
    func accepts(_ value: Int?) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active && value == generation
    }
    func beginFlush() -> Int? {
        lock.lock(); defer { lock.unlock() }
        guard active else { return nil }
        closing = true; return generation
    }
    @discardableResult
    func finish(_ expected: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard active && generation == expected else { return false }
        active = false; closing = false
        return true
    }
}

/// Bounds queued encoded bytes as well as disk writes; reserves one final cap marker.
struct TerminalEvidenceBudget {
    var maximumBytes = 64 * 1024 * 1024
    var maximumRecords = 6000
    private(set) var bytes = 0
    private(set) var records = 0
    private(set) var capped = false
    mutating func admit(_ size: Int) -> Bool {
        guard !capped else { return false }
        guard size > 0, size <= 64 * 1024, records < maximumRecords,
              bytes + size <= maximumBytes - 1024 else { capped = true; return false }
        bytes += size; records += 1; return true
    }
}

enum TerminalEvidence {
    static let schema = "bpt.terminal-evidence.v1"
    static func number(_ value: Double?) -> Any {
        guard let value, value.isFinite else { return NSNull() }
        return value
    }
    static func vector(_ values: [Double]?) -> Any {
        guard let values else { return NSNull() }
        return values.map { number($0) }
    }
}

/// Shared by the existing VideoRunLog numeric mode and the disk/error regression tests.
/// Admission encodes before enqueue (bounded memory); a failed write suppresses all later writes,
/// especially the otherwise misleading completed footer. There is no recovery/overwrite path.
final class TerminalEvidenceStream: @unchecked Sendable {
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "bpt.terminal-evidence-stream", qos: .utility)
    private var budget: TerminalEvidenceBudget
    private var sequence = 0
    private var encodingStopped = false
    private var writeFailed = false // queue only
    private let output: (Data) throws -> Void

    init(maximumBytes: Int = 64 * 1024 * 1024, maximumRecords: Int = 6000,
         output: @escaping (Data) throws -> Void) {
        budget = TerminalEvidenceBudget(maximumBytes: maximumBytes, maximumRecords: maximumRecords)
        self.output = output
    }

    private func enqueue(_ data: Data) {
        queue.async { [self] in
            guard !writeFailed else { return }
            do { try output(data) }
            catch { writeFailed = true; print("[TerminalEvidence] write_failed; incomplete") }
        }
    }

    func append(_ type: String, _ fields: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        guard !encodingStopped, !budget.capped else { return }
        var line = fields
        line["type"] = type; line["schema"] = TerminalEvidence.schema; line["sequence"] = sequence
        guard JSONSerialization.isValidJSONObject(line),
              let encoded = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else {
            encodingStopped = true
            print("[TerminalEvidence] serialization_failed; incomplete")
            return
        }
        let data = encoded + Data("\n".utf8)
        if budget.admit(data.count) {
            sequence += 1
            enqueue(data)
        } else {
            let marker = Data("{\"schema\":\"bpt.terminal-evidence.v1\",\"type\":\"terminal_capped\",\"sequence\":\(sequence),\"incomplete\":true}\n".utf8)
            enqueue(marker)
        }
    }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        encodingStopped = true // a missing candidate event must never precede a complete footer
    }

    /// Used for explicit test/export synchronization; capture callbacks never block on disk.
    func drain() { queue.sync {} }
}

/// Diagnostic EOF fence: wait only for work already accepted by the serial processing queue.
/// It does not request another source frame or inference and does not change normal endSet.
enum TerminalEvidenceIngressFence {
    static func afterPending(on queue: DispatchQueue, completion: @escaping @Sendable () -> Void) {
        queue.async(execute: completion)
    }
}

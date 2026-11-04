import Foundation

/// Original video identity, created on the decoding thread before delivery/enqueue.
struct CameraSourceFrame: Sendable, Equatable {
    let sourceID: String
    let sourceIndex: Int
}

/// Immutable per-setup binding. An old feeder keeps this binding even after a new setup installs a handler.
struct CameraIngressBinding: Sendable {
    let generation: String
    let faultRunID: String?
    init(generation: String = UUID().uuidString, faultRunID: String?) {
        self.generation = generation; self.faultRunID = faultRunID
    }
    func frame(processingFrame: Int, source: CameraSourceFrame?) -> CameraFrameIngress {
        CameraFrameIngress(generation:generation,faultRunID:faultRunID,
            sourceIndex:source?.sourceIndex ?? processingFrame,
            sourceID:source?.sourceID ?? generation)
    }
}

struct CameraFrameIngress: Sendable, Equatable {
    let generation: String
    let faultRunID: String?
    let sourceIndex: Int
    let sourceID: String
}

/// A handler is snapshotted before queueing; reading the mutable route inside queued work would relabel it.
final class CameraIngressRoute<Handler>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Handler?
    func install(_ handler: Handler?) { lock.lock(); value = handler; lock.unlock() }
    func snapshot() -> Handler? { lock.lock(); defer { lock.unlock() }; return value }
}

/// Shared consumption gate. Old work may finish computing, but cannot update a newer setup's pipeline/UI.
final class CameraIngressGeneration: @unchecked Sendable {
    private let lock = NSLock()
    private var current: String?
    private var ingressOpen = false
    func activate(_ generation: String?) {
        lock.lock(); current = generation; ingressOpen = generation != nil; lock.unlock()
    }
    /// Stop new input while retaining the current identity for already-produced/draining results.
    func stopIngress() { lock.lock(); ingressOpen = false; lock.unlock() }
    func acceptsIngress(_ generation: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; return ingressOpen && current == generation
    }
    func acceptsIngress(_ frame: CameraFrameIngress) -> Bool { acceptsIngress(frame.generation) }
    func snapshot() -> String? { lock.lock(); defer { lock.unlock() }; return current }
    func accepts(_ generation: String) -> Bool {
        lock.lock(); defer { lock.unlock() }; return current == generation
    }
    func accepts(_ frame: CameraFrameIngress?) -> Bool {
        guard let frame else { return false }; return accepts(frame.generation)
    }
}

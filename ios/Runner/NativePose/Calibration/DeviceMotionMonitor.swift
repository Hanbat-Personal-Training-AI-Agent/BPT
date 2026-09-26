import CoreMotion
import Foundation

/// Phone attitude and shake for the calibration judging engine.
///
/// Roll and pitch come from gravity so they are absolute (no gyro drift), and are
/// defined for a phone standing upright in portrait: both are 0 when the screen is
/// vertical and facing the user.
final class DeviceMotionMonitor {
    private let manager = CMMotionManager()
    private let queue = OperationQueue()
    private var latest = CalibrationDeviceState(rollDeg: 0, pitchDeg: 0, userAccelerationG: 0,
                                                rotationRateRadPerSec: 0, gravity: [0, -1, 0],
                                                isAvailable: false)
    private let lock = NSLock()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let g = motion.gravity
            // Portrait upright: gravity points down the screen (0, -1, 0).
            let rollDeg = atan2(g.x, -g.y) * 180 / .pi
            let pitchDeg = atan2(g.z, hypot(g.x, g.y)) * 180 / .pi
            let a = motion.userAcceleration
            let r = motion.rotationRate
            let state = CalibrationDeviceState(
                rollDeg: rollDeg,
                pitchDeg: pitchDeg,
                userAccelerationG: sqrt(a.x * a.x + a.y * a.y + a.z * a.z),
                rotationRateRadPerSec: sqrt(r.x * r.x + r.y * r.y + r.z * r.z),
                gravity: [g.x, g.y, g.z],
                isAvailable: true
            )
            self.lock.lock()
            self.latest = state
            self.lock.unlock()
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    var state: CalibrationDeviceState {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }
}

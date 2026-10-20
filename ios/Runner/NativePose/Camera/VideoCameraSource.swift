import AVFoundation
import CryptoKit
import QuartzCore
import SwiftUI
import UIKit

// MARK: - Options (test-only, default OFF)

/// "Video as camera" for device experiments on the real Runner camera path (ai/lift-app only; nothing changes unless
/// BPT_CAMERA_VIDEO is set at launch).
///
///   BPT_CAMERA_VIDEO=<file>[,<file>…]   paths relative to the app's Documents (or absolute)
///   BPT_CAMERA_VIDEO_LOOPS=N            play the list N times (default 1; thermal runs loop)
///   BPT_FEEDBACK_ALL_KEYS=1             NON-DEFAULT: every warning key reaches Flutter (what the user WOULD get)
///   BPT_BONE_TARGETS=<file>             the clip subject's bone lengths for Pose3DConstraints (a calibration result /
///                                       boneLengthData JSON, BoneLengthConstraint.loadTargets), Documents-relative or
///                                       absolute; one subject per launch (the driver launches once per clip)
///
/// The clip is decoded to BGRA (AVAssetReader) and paced at its own timestamps; every frame goes to the preview
/// (AVSampleBufferDisplayLayer, so preview cost is included) and to the camera manager's frame entry with the same
/// drop rule as AVCaptureVideoDataOutput.alwaysDiscardsLateVideoFrames (a frame that arrives while the processing
/// queue is still busy with the previous one is discarded). Everything after that entry is the unmodified app path.
/// Not emulated: camera capture itself, the front camera's mirroring (clips are fed as recorded), auto exposure.
enum VideoCameraOptions {
    static let environment = ProcessInfo.processInfo.environment

    static let clips: [URL] = {
        guard let list = environment["BPT_CAMERA_VIDEO"], !list.isEmpty else { return [] }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return list.split(separator: ",").map { item in
            let path = String(item).trimmingCharacters(in: .whitespaces)
            return path.hasPrefix("/") ? URL(fileURLWithPath: path) : documents.appendingPathComponent(path)
        }
    }()

    static var isActive: Bool { !clips.isEmpty }
    static let loops = max(1, Int(environment["BPT_CAMERA_VIDEO_LOOPS"] ?? "") ?? 1)
    static let allFeedbackKeys = environment["BPT_FEEDBACK_ALL_KEYS"] == "1"
    /// nil = the app default (session median / population prior, as without a calibration result).
    static let boneTargetsCm: [String: Double]? = {
        guard let name = environment["BPT_BONE_TARGETS"], !name.isEmpty else { return nil }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = name.hasPrefix("/") ? URL(fileURLWithPath: name) : documents.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), let targets = try? BoneLengthConstraint.loadTargets(json: data),
              !targets.isEmpty else { return nil }
        return targets
    }()
}

// MARK: - Source

final class VideoCameraSource: @unchecked Sendable {
    let displayLayer = AVSampleBufferDisplayLayer()
    private let urls: [URL]
    private let loops: Int
    /// Returns false when the frame was dropped (processing queue busy).
    private let deliver: (CMSampleBuffer, CFTimeInterval) -> Bool
    private let onFinish: () -> Void
    private let lock = NSLock()
    private var cancelled = false

    init(urls: [URL], loops: Int, deliver: @escaping (CMSampleBuffer, CFTimeInterval) -> Bool,
         onFinish: @escaping () -> Void) {
        self.urls = urls
        self.loops = loops
        self.deliver = deliver
        self.onFinish = onFinish
        displayLayer.videoGravity = .resizeAspectFill
    }

    func start() {
        let thread = Thread { [self] in run() }
        thread.name = "bpt.video-camera"
        thread.qualityOfService = .userInitiated
        thread.start()
    }

    func stop() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    private func run() {
        for loop in 0..<loops {
            for url in urls {
                if isCancelled { return }
                play(url, loop: loop)
            }
        }
        VideoRunLog.shared?.write("video_end", ["loops": loops, "clips": urls.map(\.lastPathComponent)])
        onFinish()
    }

    private func play(_ url: URL, loop: Int) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else {
            VideoRunLog.shared?.write("clip_error", ["clip": url.lastPathComponent])
            return
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        reader.startReading()
        VideoRunLog.shared?.write("clip_start", ["clip": url.lastPathComponent, "loop": loop,
                                                 "fps": Double(track.nominalFrameRate),
                                                 "size": [Int(track.naturalSize.width), Int(track.naturalSize.height)]])
        let clipStart = CACurrentMediaTime()
        var firstPTS: Double?
        var frames = 0, accepted = 0
        while !isCancelled, let sampleBuffer = output.copyNextSampleBuffer() {
            let pts = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            if firstPTS == nil { firstPTS = pts }
            let due = clipStart + (pts - (firstPTS ?? pts))
            let wait = due - CACurrentMediaTime()
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            let arrival = CACurrentMediaTime()
            show(sampleBuffer)
            frames += 1
            if deliver(sampleBuffer, arrival) { accepted += 1 }
        }
        reader.cancelReading()
        VideoRunLog.shared?.write("clip_end", ["clip": url.lastPathComponent, "loop": loop, "frames": frames,
                                               "delivered": accepted,
                                               "seconds": CACurrentMediaTime() - clipStart])
    }

    /// Preview: every decoded frame, shown at once (like the camera preview, independent of processing).
    private func show(_ sampleBuffer: CMSampleBuffer) {
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        if #available(iOS 17.0, *) {
            let renderer = displayLayer.sampleBufferRenderer
            if renderer.status == .failed { renderer.flush() }
            renderer.enqueue(sampleBuffer)
        } else {
            if displayLayer.status == .failed { displayLayer.flush() }
            displayLayer.enqueue(sampleBuffer)
        }
    }
}

// MARK: - Preview

struct VideoPreviewLayerView: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> VideoPreviewUIView {
        let view = VideoPreviewUIView()
        view.attach(layer)
        return view
    }

    func updateUIView(_ uiView: VideoPreviewUIView, context: Context) {
        uiView.attach(layer)
    }
}

final class VideoPreviewUIView: UIView {
    private weak var displayLayer: AVSampleBufferDisplayLayer?

    func attach(_ layer: AVSampleBufferDisplayLayer) {
        guard displayLayer !== layer else { return }
        displayLayer?.removeFromSuperlayer()
        self.layer.addSublayer(layer)
        displayLayer = layer
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer?.frame = bounds
    }
}

// MARK: - Run log

/// JSON lines under Documents/video_runs/ for one video-as-camera launch: clip start/end, every judged frame (3D state,
/// latency), every onPoseUpdate / onFeedback with its Flutter reply time, every rep report (2D and 3D metrics and
/// warnings), every line Flutter asked the Kori voice to speak, one tick per second (frames, drops, judged, XS
/// inferences, process CPU, thermal, battery). Only exists in video mode.
final class VideoRunLog: @unchecked Sendable {
    static let shared: VideoRunLog? = VideoCameraOptions.isActive ? VideoRunLog() : nil

    let url: URL
    let t0 = CACurrentMediaTime()
    private let queue = DispatchQueue(label: "bpt.video-run-log", qos: .utility)
    private var handle: FileHandle?
    private let lock = NSLock()
    private var counters: [String: Int] = [:]
    private var lastCounters: [String: Int] = [:]
    private var timer: DispatchSourceTimer?
    private var lastTick = CACurrentMediaTime()
    private var lastCPU = VideoRunLog.cpuSeconds()

    private init?() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = documents.appendingPathComponent("video_runs", isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        // BPT_RUN_TAG gives a fixed name (the host pulls exactly that file); otherwise a timestamp.
        let name = VideoCameraOptions.environment["BPT_RUN_TAG"].map { "run_\($0)" } ?? "run_\(formatter.string(from: Date()))"
        url = directory.appendingPathComponent("\(name).jsonl")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: url)
            handle = try FileHandle(forWritingTo: url)
        } catch {
            return nil
        }
        write("start", [
            "env": VideoCameraOptions.environment.filter { $0.key.hasPrefix("BPT_") },
            "device": Self.deviceModel(),
            "os": UIDevice.current.systemVersion,
            "app": Bundle.main.bundleIdentifier ?? "",
            "models": Self.bundledModelHashes(),
        ])
        startTicks()
    }

    /// Seconds since this log started.
    func rel(_ t: CFTimeInterval) -> Double { ((t - t0) * 1000).rounded() / 1000 }

    func count(_ name: String, _ n: Int = 1) {
        lock.lock()
        counters[name, default: 0] += n
        lock.unlock()
    }

    func write(_ type: String, _ fields: [String: Any]) {
        var line = fields
        line["type"] = type
        line["t"] = rel(CACurrentMediaTime())
        queue.async { [self] in
            guard let data = try? JSONSerialization.data(withJSONObject: line, options: [.sortedKeys]) else { return }
            try? handle?.write(contentsOf: data + Data("\n".utf8))
        }
    }

    private func startTicks() {
        DispatchQueue.main.async { UIDevice.current.isBatteryMonitoringEnabled = true }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        let now = CACurrentMediaTime(), cpu = Self.cpuSeconds()
        lock.lock()
        let current = counters
        lock.unlock()
        let span = max(now - lastTick, 1e-3)
        var line: [String: Any] = ["span": (span * 1000).rounded() / 1000,
                                   "cpu_pct": ((cpu - lastCPU) / span * 1000).rounded() / 10,
                                   "thermal": WorkoutPerfLog.thermalName(ProcessInfo.processInfo.thermalState)]
        for (name, value) in current { line[name] = value - (lastCounters[name] ?? 0) }
        lastCounters = current
        lastTick = now
        lastCPU = cpu
        DispatchQueue.main.async { [self] in
            line["battery"] = UIDevice.current.batteryLevel
            line["battery_state"] = UIDevice.current.batteryState.rawValue
            write("tick", line)
        }
    }

    static func cpuSeconds() -> Double {
        var u = rusage()
        getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
    }

    static func deviceModel() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    /// sha256 of every file of the compiled models the app loads (what actually runs on the phone).
    static func bundledModelHashes() -> [String: [String: String]] {
        var out: [String: [String: String]] = [:]
        for name in ["motionagformer_xs", RTMPoseModel.workout.rawValue] {
            guard let root = Bundle.main.url(forResource: name, withExtension: "mlmodelc"),
                  let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { continue }
            var hashes: [String: String] = [:]
            for case let file as URL in files where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                guard let data = try? Data(contentsOf: file) else { continue }
                let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                hashes[String(file.path.dropFirst(root.path.count + 1))] = digest
            }
            out["\(name).mlmodelc"] = hashes
        }
        return out
    }
}

import AVFoundation
import Flutter
import UIKit

/// Flutter platform view for the body calibration camera.
///
/// Native side owns the camera, perception and the judging engine; Dart gets state events
/// (`onCalibrationUpdate`, `onCalibrationError`) and draws the silhouette guide, guidance
/// text and progress. Dart drives the lifecycle with `start(userHeightCm:)` and `cancel`.
final class CalibrationCameraPlatformView: NSObject, FlutterPlatformView {
    private let container = PreviewContainerView()
    private let debugLabel = UILabel()
    private let channel: FlutterMethodChannel
    private var session: CalibrationSession!

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "bpt/body_scan_camera/\(viewId)", binaryMessenger: messenger)
        super.init()

        session = CalibrationSession(
            onUpdate: { [weak self] update in self?.send(update) },
            onError: { [weak self] message in
                self?.channel.invokeMethod("onCalibrationError", arguments: ["error": message])
            }
        )

        container.frame = frame
        container.backgroundColor = .black
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Front camera previews mirror by default (automaticallyAdjustsVideoMirroring), which is what
        // the user expects; the data output that is judged and saved is set to unmirrored.
        container.previewLayer.session = session.captureSession
        container.previewLayer.videoGravity = .resizeAspectFill

        if CalibrationDebugLog.isEnabled {
            debugLabel.numberOfLines = 0
            debugLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            debugLabel.textColor = .green
            debugLabel.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            debugLabel.frame = CGRect(x: 8, y: 120, width: frame.width - 16, height: 160)
            debugLabel.autoresizingMask = [.flexibleWidth]
            container.addSubview(debugLabel)
        }

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return result(nil) }
            switch call.method {
            case "start":
                let args = call.arguments as? [String: Any]
                session.start(userHeightCm: (args?["userHeightCm"] as? NSNumber)?.doubleValue ?? 0)
                result(nil)
            case "cancel":
                session.cancel()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    func view() -> UIView { container }

    private func send(_ update: CalibrationSession.Update) {
        if CalibrationDebugLog.isEnabled {
            let values = update.debug
                .sorted { $0.key < $1.key }
                .map { String(format: "%@ %.2f", $0.key, $0.value) }
                .joined(separator: "  ")
            debugLabel.text = """
            \(update.guidance.message)
            target \(update.targetView ?? "-")  class \(update.classifiedView ?? "-")  \
            hold \(String(format: "%.2f", update.holdProgress))
            \(values)
            """
        }
        channel.invokeMethod("onCalibrationUpdate", arguments: [
            "guidance": update.guidance.message,
            "classifiedView": update.classifiedView as Any,
            "targetView": update.targetView as Any,
            "capturedViews": update.capturedViews,
            "holdProgress": update.holdProgress,
            "isPassing": update.isPassing,
            "isFinished": update.isFinished,
            "sessionPath": update.sessionPath as Any,
            "debug": update.debug,
        ])
    }

    deinit {
        // The Dart side may be gone before its cancel arrives; stop() never deletes a finished run.
        session?.stop()
    }
}

/// Keeps the preview layer sized to the view through every layout pass.
private final class PreviewContainerView: UIView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}

final class CalibrationCameraPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect,
                viewIdentifier viewId: Int64,
                arguments args: Any?) -> FlutterPlatformView {
        CalibrationCameraPlatformView(frame: frame, viewId: viewId, messenger: messenger)
    }
}

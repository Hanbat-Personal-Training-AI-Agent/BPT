import AVFoundation
import Flutter
import UIKit

/// Flutter platform view for the body calibration camera.
///
/// Native side owns the camera, RTMPose and the judging engine; Dart gets state events
/// (`onCalibrationUpdate`) and draws the silhouette guide, guidance text and progress.
/// Dart drives the lifecycle with `start(userHeightCm:)` and `cancel`.
final class CalibrationCameraPlatformView: NSObject, FlutterPlatformView {
    private let container = UIView()
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let debugLabel = UILabel()
    private let channel: FlutterMethodChannel
    private var session: CalibrationSession!

    init(frame: CGRect, viewId: Int64, messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "bpt/body_scan_camera/\(viewId)", binaryMessenger: messenger)
        previewLayer = AVCaptureVideoPreviewLayer()
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

        previewLayer.session = session.captureSession
        previewLayer.videoGravity = .resizeAspectFill
        // Preview mirrors so the user sees themselves as in a mirror; judging stays unmirrored.
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        container.layer.addSublayer(previewLayer)

        if CalibrationDebugLog.isEnabled {
            debugLabel.numberOfLines = 0
            debugLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            debugLabel.textColor = .green
            debugLabel.backgroundColor = UIColor.black.withAlphaComponent(0.35)
            container.addSubview(debugLabel)
        }

        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return }
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

    func view() -> UIView {
        previewLayer.frame = container.bounds
        debugLabel.frame = CGRect(x: 8, y: 120, width: container.bounds.width - 16, height: 150)
        return container
    }

    private func send(_ update: CalibrationSession.Update) {
        previewLayer.frame = container.bounds
        if CalibrationDebugLog.isEnabled {
            let debug = update.debug
                .sorted { $0.key < $1.key }
                .map { String(format: "%@ %.3f", $0.key, $0.value) }
                .joined(separator: "  ")
            debugLabel.text = """
            \(update.guidance)
            target \(update.targetView ?? "-")  class \(update.classifiedView ?? "-")  hold \
            \(String(format: "%.2f", update.holdProgress))
            \(debug)
            """
        }
        channel.invokeMethod("onCalibrationUpdate", arguments: [
            "guidance": update.guidance,
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
        session?.stop()
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

import Flutter
import UIKit

final class NativePoseCameraPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        let params = args as? [String: Any]
        let exerciseId = params?["exerciseId"] as? String
        let exercise = exerciseId.flatMap { NativePoseExercise(flutterId: $0) }
        VideoRunLog.shared?.write("platform_view_created", ["exerciseId": exerciseId ?? "", "supported": exercise != nil])
        if params?["wristAnchor"] as? Bool == true { CameraPreviewOptions.wristAnchor = true }  // dart-define BPT_WRIST_ANCHOR

        return NativePoseCameraPlatformView(
            frame: frame,
            viewId: viewId,
            messenger: messenger,
            exercise: exercise,
            exerciseId: exerciseId,
            setupOptions: ExerciseSetup.Options(creationParams: params)  // nil unless exerciseSetup: true
        )
    }
}

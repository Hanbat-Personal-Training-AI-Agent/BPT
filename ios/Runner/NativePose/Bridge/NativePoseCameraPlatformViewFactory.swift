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
        // "strict" | "standard" | "relaxed"; missing or unknown = standard (FormStrictness).
        let strictness = FormStrictness(flutterValue: params?["formStrictness"] as? String)

        return NativePoseCameraPlatformView(
            frame: frame,
            viewId: viewId,
            messenger: messenger,
            exercise: exercise,
            exerciseId: exerciseId,
            strictness: strictness
        )
    }
}

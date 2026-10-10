import Flutter
import SwiftUI
import UIKit

final class NativePoseCameraPlatformView: NSObject, FlutterPlatformView {
    private let hostingController: UIHostingController<AnyView>
    private let workoutChannel: WorkoutChannel

    init(
        frame: CGRect,
        viewId: Int64,
        messenger: FlutterBinaryMessenger,
        exercise: NativePoseExercise?,
        exerciseId: String?
    ) {
        let workoutChannel = WorkoutChannel(channel: FlutterMethodChannel(
            name: "bpt/native_pose_camera/\(viewId)",
            binaryMessenger: messenger
        ))
        self.workoutChannel = workoutChannel

        let rootView: AnyView
        if let exercise {
            // Channel contract: WorkoutSessionBridge.swift (onPoseUpdate, onFeedback, onSetEnd ←→ setVoiceMuted, startSet, endSet).
            rootView = AnyView(CameraPosePreview(exercise: exercise, bridge: workoutChannel))
        } else {
            rootView = AnyView(UnsupportedNativePoseExerciseView(exerciseId: exerciseId))
        }

        hostingController = UIHostingController(rootView: rootView)
        super.init()

        hostingController.view.frame = frame
        hostingController.view.backgroundColor = .black
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    func view() -> UIView {
        hostingController.view
    }

    deinit {
        workoutChannel.close()
    }
}

private struct UnsupportedNativePoseExerciseView: View {
    let exerciseId: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.yellow)
                Text("Unsupported Exercise")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text("Native AI coaching does not support exercise id: \(exerciseId ?? "nil")")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
        }
    }
}

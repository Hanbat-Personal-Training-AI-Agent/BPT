import Flutter

enum NativePoseRegistration {
    static let viewType = "bpt/native_pose_camera"
    /// Body calibration keeps the original view id so the Flutter side stays unchanged.
    static let bodyScanViewType = "bpt/body_scan_camera"

    /// Kept alive for the app's lifetime; see [KoriVoiceChannel].
    private static var koriVoice: KoriVoiceChannel?

    /// Test-only (ai/lift-app device runs): BPT_AUTOSTART_WORKOUT / BPT_AUTOSTART_REPS from the launch environment go to
    /// shared_preferences (`flutter.` prefix) for lib/core/router/app_router.dart; every other launch removes them.
    private static func handOverAutostart() {
        let env = ProcessInfo.processInfo.environment, defaults = UserDefaults.standard
        if let workout = env["BPT_AUTOSTART_WORKOUT"], !workout.isEmpty {
            defaults.set(workout, forKey: "flutter.bpt_autostart_workout")
            defaults.set(env["BPT_AUTOSTART_REPS"] ?? "", forKey: "flutter.bpt_autostart_reps")
        } else {
            defaults.removeObject(forKey: "flutter.bpt_autostart_workout")
            defaults.removeObject(forKey: "flutter.bpt_autostart_reps")
        }
    }

    static func register(with registry: FlutterPluginRegistry) {
        VideoRunLog.shared?.write("app_registered", [:])  // test-only breadcrumb (video-as-camera launches)
        handOverAutostart()
        DemoScreenRecorder.install()  // trial branch only; no-op without BPT_SCREEN_RECORD
        if let registrar = registry.registrar(forPlugin: "KoriVoiceChannel") {
            koriVoice = KoriVoiceChannel(messenger: registrar.messenger())
        }

        if let registrar = registry.registrar(forPlugin: "NativePoseCameraPlatformView") {
            registrar.register(
                NativePoseCameraPlatformViewFactory(messenger: registrar.messenger()),
                withId: viewType
            )
        }

        if let registrar = registry.registrar(forPlugin: "CalibrationCameraPlatformView") {
            registrar.register(
                CalibrationCameraPlatformViewFactory(messenger: registrar.messenger()),
                withId: bodyScanViewType
            )
        }
    }
}

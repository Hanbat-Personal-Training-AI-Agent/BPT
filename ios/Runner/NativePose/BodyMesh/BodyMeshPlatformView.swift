import Flutter
import SceneKit
import UIKit

/// Flutter platform view `bpt/body_mesh`: the user's SMPL body (GLB bytes in the creation
/// params, `glb`) in BPT colours. Card-style entrance (rises and flips in, scale overshoot)
/// with a light sweep, then a slow auto-turn until the first touch. Drag: yaw free,
/// pitch ±15°. No zoom, no pan. Dart: lib/features/onboarding/widgets/body_mesh_reveal.dart.
final class BodyMeshPlatformView: NSObject, FlutterPlatformView {
    /// The visible view, for the channel's `spin` (demo recording).
    static weak var current: BodyMeshPlatformView?
    static var channel: FlutterMethodChannel?

    private static let maxPitch = Float.pi / 12  // 15°
    private static let revealSeconds = 1.3

    private let scnView = SCNView()
    private let stage = SCNNode()  // entrance: position, scale, opacity
    private let pitchNode = SCNNode()  // tilt toward the camera (outer)
    private let yawNode = SCNNode()  // turn about the body's vertical axis
    private let material = SCNMaterial()
    private var interactive = false

    init(frame: CGRect, arguments: Any?) {
        super.init()
        scnView.frame = frame
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = .clear
        scnView.isOpaque = false
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false
        scnView.rendersContinuously = true  // the shader's sweep value is not a scene change
        let scene = SCNScene()
        scnView.scene = scene

        let bytes = ((arguments as? [String: Any])?["glb"] as? FlutterStandardTypedData)?.data
        var parsed: GLBMesh?
        var parseError = ""
        if let bytes {
            do { parsed = try GLBMesh(data: bytes) } catch { parseError = "\(error)" }
        }
        Self.writeDiag(bytes: bytes, mesh: parsed, error: parseError, frame: frame)
        guard let mesh = parsed else {
            DispatchQueue.main.async { Self.channel?.invokeMethod("onMeshError", arguments: nil) }
            return
        }
        Self.current = self

        let height = mesh.yRange.upperBound - mesh.yRange.lowerBound
        let body = SCNNode(geometry: Self.geometry(mesh))
        body.position = SCNVector3(0, -(mesh.yRange.lowerBound + height / 2), 0)  // turn about the body centre
        body.geometry?.firstMaterial = material
        configureMaterial()

        scene.rootNode.addChildNode(stage)
        stage.addChildNode(pitchNode)
        pitchNode.addChildNode(yawNode)
        yawNode.addChildNode(body)

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.automaticallyAdjustsZRange = true
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        // Whole body plus a margin, at a 30° vertical field of view.
        cameraNode.position = SCNVector3(0, 0, 0.62 * height / tan(Float.pi / 12))
        scene.rootNode.addChildNode(cameraNode)
        scnView.pointOfView = cameraNode

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 900
        key.eulerAngles = SCNVector3(-0.5, -0.5, 0)
        scene.rootNode.addChildNode(key)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 350
        scene.rootNode.addChildNode(ambient)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        scnView.addGestureRecognizer(pan)

        reveal()
    }

    func view() -> UIView { scnView }

    /// TRIAL BRANCH ONLY (demo diagnosis, BPT_POSE3D_LOG=1): what arrived and where it sits. Writes
    /// Documents/demo/mesh_diag.json and keeps the GLB as Documents/demo/body_mesh.glb (the user's body: phone only).
    private static func writeDiag(bytes: Data?, mesh: GLBMesh?, error: String, frame: CGRect) {
        guard DemoConfig.environment["BPT_POSE3D_LOG"] == "1",
              let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = documents.appendingPathComponent("demo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var info: [String: Any] = ["bytes": bytes?.count ?? -1, "error": error,
                                   "frame": [frame.origin.x, frame.origin.y, frame.width, frame.height]]
        if let bytes { try? bytes.write(to: dir.appendingPathComponent("body_mesh.glb")) }
        if let mesh {
            let xs = mesh.positions.map(\.x), ys = mesh.positions.map(\.y), zs = mesh.positions.map(\.z)
            info["vertices"] = mesh.positions.count
            info["triangles"] = mesh.indices.count / 3
            info["min"] = [xs.min() ?? 0, ys.min() ?? 0, zs.min() ?? 0]
            info["max"] = [xs.max() ?? 0, ys.max() ?? 0, zs.max() ?? 0]
            let height = mesh.yRange.upperBound - mesh.yRange.lowerBound
            info["height"] = height
            info["camera_z"] = 0.62 * height / tan(Float.pi / 12)
        }
        if let data = try? JSONSerialization.data(withJSONObject: info, options: [.sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("mesh_diag.json"))
        }
    }

    private static func geometry(_ mesh: GLBMesh) -> SCNGeometry {
        let vertices = SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) })
        let normals = SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) })
        let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
        return SCNGeometry(sources: [vertices, normals], elements: [element])
    }

    /// BPT purple body, green rim light, and a white diagonal band (`sweep`, view-space metres)
    /// that crosses the body once, like light over a new card.
    private func configureMaterial() {
        material.lightingModel = .blinn
        material.diffuse.contents = UIColor(red: 0.675, green: 0.533, blue: 0.965, alpha: 1)  // AppColors.purple
        material.specular.contents = UIColor(white: 0.35, alpha: 1)
        material.shininess = 0.25
        material.shaderModifiers = [.fragment: """
        #pragma arguments
        float sweep;
        #pragma body
        float3 n = normalize(_surface.normal);
        float3 v = normalize(-_surface.position);
        float rim = pow(1.0 - saturate(dot(n, v)), 2.5);
        _output.color.rgb += float3(0.749, 0.929, 0.373) * rim * 1.2;
        float d = _surface.position.y * 0.8 + _surface.position.x * 0.6;
        float band = exp(-pow((d - sweep) * 8.0, 2.0));
        _output.color.rgb += float3(1.0, 1.0, 0.92) * band * 0.85;
        """]
        material.setValue(NSNumber(value: -9.0), forKey: "sweep")
    }

    private func reveal() {
        stage.position = SCNVector3(0, -1.2, 0)
        stage.scale = SCNVector3(0.6, 0.6, 0.6)
        stage.opacity = 0
        yawNode.eulerAngles.y = -.pi

        let rise = SCNAction.move(to: SCNVector3(0, 0, 0), duration: Self.revealSeconds)
        rise.timingMode = .easeOut
        let grow = SCNAction.sequence([
            .scale(to: 1.06, duration: Self.revealSeconds * 0.8),
            .scale(to: 1.0, duration: Self.revealSeconds * 0.3),
        ])
        grow.timingMode = .easeOut
        stage.runAction(.group([rise, grow, .fadeIn(duration: 0.4)]))

        let flip = SCNAction.rotateTo(x: 0, y: 0, z: 0, duration: Self.revealSeconds, usesShortestUnitArc: false)
        flip.timingMode = .easeOut
        let shineSeconds = 0.8
        let shine = SCNAction.customAction(duration: shineSeconds) { [weak self] _, elapsed in
            let t = Double(elapsed) / shineSeconds
            self?.material.setValue(NSNumber(value: -1.6 + 3.2 * t), forKey: "sweep")
        }
        let idle = SCNAction.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 24))
        yawNode.runAction(.sequence([
            flip,
            .run { [weak self] _ in DispatchQueue.main.async { self?.interactive = true } },
            .group([shine, idle]),
        ]), forKey: "reveal")
    }

    @objc private func onPan(_ pan: UIPanGestureRecognizer) {
        guard interactive else { return }
        yawNode.removeAllActions()  // the auto-turn stops at the first touch
        material.setValue(NSNumber(value: -9.0), forKey: "sweep")
        let d = pan.translation(in: scnView)
        pan.setTranslation(.zero, in: scnView)
        yawNode.eulerAngles.y += Float(d.x) * 0.012
        pitchNode.eulerAngles.x = min(max(pitchNode.eulerAngles.x + Float(d.y) * 0.004, -Self.maxPitch), Self.maxPitch)
    }

    /// Slow scripted turn, eased like a hand drag, with a small tilt and back.
    func spin(turns: Double, seconds: Double) {
        interactive = true
        yawNode.removeAllActions()
        let turn = SCNAction.rotateBy(x: 0, y: CGFloat(2 * .pi * turns), z: 0, duration: seconds)
        turn.timingMode = .easeInEaseOut
        yawNode.runAction(turn)
        let tilt = CGFloat(Self.maxPitch * 0.6)
        pitchNode.runAction(.sequence([
            .rotateTo(x: tilt, y: 0, z: 0, duration: seconds * 0.4),
            .rotateTo(x: 0, y: 0, z: 0, duration: seconds * 0.4),
        ]))
    }
}

final class BodyMeshPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    init(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: "bpt/body_mesh", binaryMessenger: messenger)
        channel.setMethodCallHandler { call, result in
            guard call.method == "spin" else { return result(FlutterMethodNotImplemented) }
            let args = call.arguments as? [String: Any]
            BodyMeshPlatformView.current?.spin(turns: (args?["turns"] as? NSNumber)?.doubleValue ?? 1,
                                               seconds: (args?["seconds"] as? NSNumber)?.doubleValue ?? 7)
            result(nil)
        }
        BodyMeshPlatformView.channel = channel
        super.init()
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        FlutterStandardMessageCodec.sharedInstance()
    }

    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        BodyMeshPlatformView(frame: frame, arguments: args)
    }
}

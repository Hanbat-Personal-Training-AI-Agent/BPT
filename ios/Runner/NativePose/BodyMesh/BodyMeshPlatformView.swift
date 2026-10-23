import Flutter
import SceneKit
import UIKit
import os.log

/// SceneKit waits for Flutter's first non-zero layout before fitting the camera or fading in.
private final class BodyMeshSceneView: SCNView {
    var onLayout: ((CGSize) -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width > 0 && bounds.height > 0 { onLayout?(bounds.size) }
    }
}

/// Small, prepared body preview. Drag: yaw free, pitch ±15°. No zoom or pan.
final class BodyMeshPlatformView: NSObject, FlutterPlatformView, UIGestureRecognizerDelegate {
    static weak var current: BodyMeshPlatformView?
    static var channel: FlutterMethodChannel?
    private static let worker = DispatchQueue(label: "bpt.body-mesh.prepare", qos: .userInitiated)
    // Accessed only on the main thread; one pending result, consumed by the next view.
    private static var prepared: (id: String, mesh: PreparedMesh)?
    private static let log = OSLog(subsystem: "bpt.body_mesh", category: "render")
    private static let maxPitch = Float.pi / 12

    private struct PreparedMesh {
        let geometry: SCNGeometry
        let vertexCount: Int
        let sourceBounds: String
    }

    private let scnView = BodyMeshSceneView()
    private let stage = SCNNode()
    private let pitchNode = SCNNode()
    private let yawNode = SCNNode()
    private let cameraNode = SCNNode()
    private var revealed = false
    private var touched = false

    /// Parse, generate normals and create geometry before leaving the analysis screen.
    static func prepare(_ data: Data, result: @escaping FlutterResult) {
        worker.async {
            do {
                let source = try GLBMesh(data: data)
                let mesh = try source.centeredYUp()
                let vertices = SCNGeometrySource(vertices: mesh.positions.map { SCNVector3($0.x, $0.y, $0.z) })
                let normals = SCNGeometrySource(normals: mesh.normals.map { SCNVector3($0.x, $0.y, $0.z) })
                let element = SCNGeometryElement(indices: mesh.indices, primitiveType: .triangles)
                let geometry = SCNGeometry(sources: [vertices, normals], elements: [element])
                let ready = PreparedMesh(geometry: geometry, vertexCount: mesh.positions.count,
                                         sourceBounds: "\(source.bounds.min)...\(source.bounds.max)")
                DispatchQueue.main.async {
                    let id = UUID().uuidString
                    prepared = (id, ready)
                    result(id)
                }
            } catch {
                DispatchQueue.main.async {
                    os_log("메시 준비 실패", log: log, type: .error)
                    result(FlutterError(code: "mesh_format", message: "3D 모형을 준비하지 못했어요.", details: nil))
                }
            }
        }
    }

    static func release(_ id: String?) {
        if prepared?.id == id { prepared = nil }
    }

    init(frame: CGRect, arguments: Any?) {
        super.init()
        // Flutter creates UIKit platform views on the platform (main) thread.
        dispatchPrecondition(condition: .onQueue(.main))
        scnView.frame = frame
        scnView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scnView.backgroundColor = .clear
        scnView.isOpaque = false
        scnView.antialiasingMode = .multisampling4X
        scnView.allowsCameraControl = false
        scnView.rendersContinuously = true
        scnView.isPlaying = true
        let scene = SCNScene()
        scnView.scene = scene

        let id = (arguments as? [String: Any])?["meshId"] as? String
        guard let ready = Self.prepared, ready.id == id else {
            DispatchQueue.main.async { Self.channel?.invokeMethod("onMeshError", arguments: id) }
            return
        }
        Self.prepared = nil
        Self.current = self
        let body = SCNNode(geometry: ready.mesh.geometry)
        body.geometry?.firstMaterial = Self.material()
        // Geometry is already Y-up and unit height; verify the actual SceneKit node bounds.
        let box = body.boundingBox
        let centre = SIMD3<Float>((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2,
                                  (box.min.z + box.max.z) / 2)
        body.simdPosition = -centre
        let halfSize = SIMD3<Float>(box.max.x - box.min.x, box.max.y - box.min.y, box.max.z - box.min.z) / 2
        let radius = simd_length(halfSize)
        guard radius.isFinite, radius > 0 else {
            DispatchQueue.main.async { Self.channel?.invokeMethod("onMeshError", arguments: id) }
            return
        }
        scene.rootNode.addChildNode(stage)
        stage.addChildNode(pitchNode)
        pitchNode.addChildNode(yawNode)
        yawNode.addChildNode(body)

        let camera = SCNCamera()
        camera.fieldOfView = 35
        camera.projectionDirection = .vertical
        cameraNode.camera = camera
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
        pan.delegate = self
        scnView.addGestureRecognizer(pan)
        scnView.onLayout = { [weak self] size in
            guard let self else { return }
            let distance = GLBMesh.cameraDistance(radius: radius, aspect: Float(size.width / size.height))
            self.cameraNode.position = SCNVector3(0, 0, distance)
            camera.zNear = Double(max(0.001, distance - radius * 1.5))
            camera.zFar = Double(distance + radius * 2)
            if !self.revealed {
                self.revealed = true
                os_log("메시 정점=%d bbox=%{public}@ camera=%.3f frame=%.0fx%.0f", log: Self.log, type: .info,
                       ready.mesh.vertexCount, ready.mesh.sourceBounds, distance, size.width, size.height)
                self.reveal()
            }
        }
        scnView.setNeedsLayout()
    }

    func view() -> UIView { scnView }

    private static func material() -> SCNMaterial {
        let material = SCNMaterial()
        material.isDoubleSided = true
        material.lightingModel = .blinn
        material.diffuse.contents = UIColor(red: 172 / 255.0, green: 136 / 255.0, blue: 246 / 255.0, alpha: 1)
        material.specular.contents = UIColor(white: 0.35, alpha: 1)
        material.shininess = 0.25
        material.shaderModifiers = [.fragment: """
        #pragma body
        float3 n = normalize(_surface.normal);
        float3 v = normalize(-_surface.position);
        float rim = pow(1.0 - saturate(abs(dot(n, v))), 2.5);
        _output.color.rgb += float3(0.749, 0.929, 0.373) * rim * 0.8;
        """]
        return material
    }

    private func reveal() {
        stage.scale = SCNVector3(0.96, 0.96, 0.96)
        stage.opacity = 0
        let entrance = SCNAction.group([.scale(to: 1, duration: 0.6), .fadeIn(duration: 0.6)])
        entrance.timingMode = .easeOut
        stage.runAction(entrance)
        if !touched {
            yawNode.runAction(.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 24)))
        }
    }

    private func stopRotation() {
        touched = true
        let yaw = yawNode.presentation.eulerAngles.y
        let pitch = pitchNode.presentation.eulerAngles.x
        yawNode.removeAllActions()
        pitchNode.removeAllActions()
        yawNode.eulerAngles.y = yaw
        pitchNode.eulerAngles.x = pitch
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        stopRotation()  // Stops even on a tap, before the pan recognizer crosses its threshold.
        return true
    }

    @objc private func onPan(_ pan: UIPanGestureRecognizer) {
        let d = pan.translation(in: scnView)
        pan.setTranslation(.zero, in: scnView)
        yawNode.eulerAngles.y += Float(d.x) * 0.012
        pitchNode.eulerAngles.x = min(max(pitchNode.eulerAngles.x + Float(d.y) * 0.004, -Self.maxPitch), Self.maxPitch)
    }

    /// Slow scripted turn, eased like a hand drag, with a small tilt and back.
    func spin(turns: Double, seconds: Double) {
        guard turns.isFinite, seconds.isFinite, seconds > 0 else { return }
        stopRotation()
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
            let args = call.arguments as? [String: Any]
            switch call.method {
            case "prepare":
                guard let bytes = (args?["glb"] as? FlutterStandardTypedData)?.data else {
                    return result(FlutterError(code: "mesh_format", message: "3D 모형 데이터가 없어요.", details: nil))
                }
                BodyMeshPlatformView.prepare(bytes, result: result)
            case "release":
                BodyMeshPlatformView.release(args?["meshId"] as? String)
                result(nil)
            case "spin":
                BodyMeshPlatformView.current?.spin(turns: (args?["turns"] as? NSNumber)?.doubleValue ?? 1,
                                                   seconds: (args?["seconds"] as? NSNumber)?.doubleValue ?? 7)
                result(nil)
            default: result(FlutterMethodNotImplemented)
            }
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

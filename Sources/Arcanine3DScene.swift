import AppKit
import SceneKit
import GLTFKit2

final class Arcanine3DScene {
    let scene = SCNScene()
    let camera = SCNNode()
    private let orientation = SCNNode()
    private(set) var yaw: Double = 0
    private var root: SCNNode?
    private var animations: [String: SCNAnimation] = [:]
    private var restTransforms: [(SCNNode, SCNMatrix4)] = []
    private(set) var jointCount = 0
    private(set) var clipCount = 0
    private(set) var ready = false
    private(set) var loadError: String?
    private var playerKey = ""
    private var sequence = 0
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?

    init() {
        scene.background.contents = NSColor.clear
        orientation.name = "ArcanineUserOrientation"
        scene.rootNode.addChildNode(orientation)
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 34
        camera.camera?.projectionDirection = .vertical
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 100
        camera.position = SCNVector3(3.2, 2.25, 5.4)
        camera.look(at: SCNVector3(0, 1.1, 0))
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode()
        ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 550; ambient.light?.color = NSColor.white
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode()
        key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 700; key.light?.color = NSColor.white
        key.eulerAngles = SCNVector3(-0.6, -0.5, 0)
        scene.rootNode.addChildNode(key)
    }

    func load() {
        guard let url = Bundle.main.url(forResource: "arcanine-biblioteca", withExtension: "glb") else {
            fail("Falta el modelo 3D. Vuelve a construir Arcanine con construir.command."); return
        }
        GLTFAsset.load(with: url, options: [:]) { [weak self] _, status, asset, error, _ in
            if let error { DispatchQueue.main.async { self?.fail(error.localizedDescription) }; return }
            guard status == .complete, let asset else { return }
            DispatchQueue.main.async { self?.install(asset) }
        }
    }

    private func install(_ asset: GLTFAsset) {
        let source = GLTFSCNSceneSource(asset: asset)
        guard let model = source.defaultScene else { fail("No pude leer la escena 3D de Arcanine."); return }
        let clips = Dictionary(uniqueKeysWithValues: source.animations.map { ($0.name, $0.animationPlayer.animation) })
        guard ArcanineClip.allCases.allSatisfy({ clips[$0.rawValue] != nil }) else {
            fail("La biblioteca de Arcanine no contiene todas las animaciones. Vuelve a construir la app."); return
        }
        let modelRoot = model.rootNode
        let box = modelRoot.boundingBox
        guard box.max.y > box.min.y else { fail("El modelo 3D no tiene una altura válida."); return }
        let scale = 2.2 / (box.max.y - box.min.y)
        let placement = SCNNode()
        placement.scale = SCNVector3(scale, scale, scale)
        placement.position = SCNVector3(-(box.max.x + box.min.x) * scale / 2, -box.min.y * scale, -(box.max.z + box.min.z) * scale / 2)
        placement.addChildNode(modelRoot)
        orientation.addChildNode(placement)
        modelRoot.enumerateChildNodes { node, _ in self.restTransforms.append((node, node.transform)) }
        root = modelRoot; animations = clips
        jointCount = asset.skins.first?.joints.count ?? 0; clipCount = clips.count
        ready = true; onReady?()
    }

    private func fail(_ message: String) { loadError = message; onError?(message) }

    func setYaw(_ value: Double) {
        let angle = PetRotation.normalized(value)
        guard yaw != angle else { return }
        yaw = angle
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        orientation.eulerAngles = SCNVector3(0, angle, 0)
        SCNTransaction.commit()
    }
    var orientationAngles: SCNVector3 { orientation.eulerAngles }

    func play(_ clip: ArcanineClip, preview: Bool = false, previewTime: TimeInterval = 0) {
        guard let root, let original = animations[clip.rawValue] else { return }
        if preview { root.removeAllAnimations() }
        else if !playerKey.isEmpty { root.removeAnimation(forKey: playerKey, blendOutDuration: 0.2) }
        let animation = original.copy() as! SCNAnimation
        animation.usesSceneTimeBase = preview
        animation.timeOffset = preview ? previewTime : 0
        animation.repeatCount = clip == .idle ? .greatestFiniteMagnitude : 0
        animation.isRemovedOnCompletion = !preview
        animation.fillsForward = preview
        animation.blendInDuration = preview ? 0 : 0.2
        animation.blendOutDuration = preview ? 0 : 0.2
        sequence += 1; playerKey = "arcanine-\(sequence)"
        let player = SCNAnimationPlayer(animation: animation)
        if preview { player.speed = 0 }
        root.addAnimationPlayer(player, forKey: playerKey)
        player.play()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = preview ? 0 : 0.3
        camera.position = clip == .chaseTail ? SCNVector3(4.1, 2.8, 7) : SCNVector3(3.2, 2.25, 5.4)
        camera.look(at: SCNVector3(0, 1.1, 0))
        SCNTransaction.commit()
    }

    func rest() {
        root?.removeAllAnimations()
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        for (node, transform) in restTransforms { node.transform = transform }
        camera.position = SCNVector3(3.2, 2.25, 5.4)
        camera.look(at: SCNVector3(0, 1.1, 0))
        SCNTransaction.commit()
    }

    func node(_ name: String) -> SCNNode? { root?.childNode(withName: name, recursively: true) }
}

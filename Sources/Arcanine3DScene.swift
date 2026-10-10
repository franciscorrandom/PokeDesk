import AppKit
import SceneKit
import GLTFKit2
import simd

final class Arcanine3DScene {
    let scene = SCNScene()
    let camera = SCNNode()
    private let appearance = SCNNode()
    private let orientation = SCNNode()
    private(set) var yaw: Double = 0
    private var root: SCNNode?
    private var animations: [String: SCNAnimation] = [:]
    private var restTransforms: [(SCNNode, SCNMatrix4)] = []
    private(set) var jointCount = 0
    private(set) var clipCount = 0
    private(set) var ready = false
    private(set) var loadError: String?
    private(set) var character: PetCharacter = .arcanine
    private(set) var loadingCharacter: PetCharacter?
    private var loadGeneration = 0
    private var playerKey = ""
    private var sequence = 0
    private var pendingYaw: Double?
    private var summon: Pokeball3DEffect?
    private var summonStarted = 0.0
    private var summonCompletion: (() -> Void)?
    private var summonPreview = false
    private var emissions: [(SCNMaterial, Any?, CGFloat)] = []
    var effectsEnabled = true { didSet { if !effectsEnabled { finishSummoningImmediately() } } }
    var isTransitioning: Bool { summon != nil }
    var summoningPhase: PetSummonPhase? { summon?.phase }
    var onSummonStarted: ((PetSummonPhase) -> Void)?
    var onSummonChanged: (() -> Void)?
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?

    init() {
        scene.background.contents = NSColor.clear
        orientation.name = "ArcanineUserOrientation"
        appearance.name = "PokemonMaterialization"
        appearance.pivot = SCNMatrix4MakeTranslation(0, 1.1, 0)
        appearance.position = SCNVector3(0, 1.1, 0)
        appearance.addChildNode(orientation)
        scene.rootNode.addChildNode(appearance)
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

    func load(character requested: PetCharacter = .arcanine) {
        guard loadingCharacter != requested else { return }
        if ready && character == requested {
            if loadingCharacter != nil {
                loadGeneration += 1; loadingCharacter = nil; pendingYaw = nil
                cancelSummoning()
            }
            return
        }
        loadGeneration += 1
        let generation = loadGeneration
        cancelSummoning()
        loadingCharacter = requested; loadError = nil
        guard let url = Bundle.main.url(forResource: requested.modelResource, withExtension: "glb") else {
            fail("Falta el modelo de \(requested.name). Vuelve a descargar la app completa."); return
        }
        GLTFAsset.load(with: url, options: [:]) { [weak self] _, status, asset, error, _ in
            DispatchQueue.main.async {
                guard let self, generation == self.loadGeneration else { return }
                if let error { self.fail(error.localizedDescription); return }
                guard status == .complete, let asset else { return }
                self.prepare(asset, character: requested, generation: generation)
            }
        }
    }

    private func prepare(_ asset: GLTFAsset, character requested: PetCharacter, generation: Int) {
        let source = GLTFSCNSceneSource(asset: asset)
        guard let model = source.defaultScene else { fail("No pude leer la escena 3D de \(requested.name)."); return }
        let clips = Dictionary(uniqueKeysWithValues: source.animations.map { ($0.name, $0.animationPlayer.animation) })
        guard requested.clips.allSatisfy({ clips[$0.rawValue] != nil }) else {
            fail("La biblioteca de \(requested.name) no contiene todas las animaciones. Vuelve a descargar la app completa."); return
        }
        let modelRoot = model.rootNode
        let box = modelRoot.boundingBox
        guard box.max.y > box.min.y else { fail("El modelo 3D no tiene una altura válida."); return }
        let scale = 2.2 / (box.max.y - box.min.y)
        let placement = SCNNode()
        placement.scale = SCNVector3(scale, scale, scale)
        placement.position = SCNVector3(-(box.max.x + box.min.x) * scale / 2, -box.min.y * scale, -(box.max.z + box.min.z) * scale / 2)
        placement.addChildNode(modelRoot)
        let install = { [weak self] in
            guard let self, generation == self.loadGeneration else { return }
            self.install(placement, root: modelRoot, clips: clips,
                         joints: asset.skins.first?.joints.count ?? 0, character: requested)
            if self.effectsEnabled {
                self.startSummoning(.release) { [weak self] in
                    guard let self, generation == self.loadGeneration else { return }
                    self.loadingCharacter = nil; self.onReady?()
                }
            } else { self.loadingCharacter = nil; self.onReady?() }
        }
        if ready && effectsEnabled {
            rest()
            startSummoning(.recall, completion: install)
        } else { install() }
    }

    private func install(_ placement: SCNNode, root modelRoot: SCNNode, clips: [String: SCNAnimation], joints: Int, character requested: PetCharacter) {
        // Replace only after validation. A failed or stale load leaves the existing pet intact.
        orientation.childNodes.forEach { $0.removeFromParentNode() }
        restTransforms.removeAll(); playerKey = ""
        orientation.addChildNode(placement)
        modelRoot.enumerateChildNodes { node, _ in self.restTransforms.append((node, node.transform)) }
        root = modelRoot; animations = clips
        jointCount = joints; clipCount = clips.count
        character = requested; loadError = nil; ready = true
        if let angle = pendingYaw { pendingYaw = nil; applyYaw(angle) }
        play(.idle)
    }

    private func fail(_ message: String) {
        cancelSummoning(); pendingYaw = nil; loadingCharacter = nil
        loadError = message; onError?(message)
    }

    func setYaw(_ value: Double) {
        if let loadingCharacter, loadingCharacter != character { pendingYaw = value; return }
        applyYaw(value)
    }
    private func applyYaw(_ value: Double) {
        let angle = PetRotation.normalized(value)
        guard yaw != angle else { return }
        yaw = angle
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        orientation.eulerAngles = SCNVector3(0, angle, 0)
        SCNTransaction.commit()
    }
    var orientationAngles: SCNVector3 { orientation.eulerAngles }

    private func startSummoning(_ phase: PetSummonPhase, completion: (() -> Void)? = nil) {
        cancelSummoning()
        var seen = Set<ObjectIdentifier>()
        root?.enumerateChildNodes { node, _ in
            for material in node.geometry?.materials ?? [] where seen.insert(ObjectIdentifier(material)).inserted {
                self.emissions.append((material, material.emission.contents, material.emission.intensity))
            }
        }
        let effect = Pokeball3DEffect(phase: phase)
        summon = effect; summonStarted = ProcessInfo.processInfo.systemUptime
        summonCompletion = completion; scene.rootNode.addChildNode(effect.node)
        applySummoning(PetSummonFrame(phase: phase, time: 0))
        onSummonStarted?(phase); onSummonChanged?()
    }

    func updateSummoning(at time: Double) {
        guard let effect = summon, !summonPreview else { return }
        let elapsed = time-summonStarted
        applySummoning(PetSummonFrame(phase: effect.phase, time: elapsed))
        if elapsed >= effect.phase.duration { completeSummoning() }
    }

    private func applySummoning(_ frame: PetSummonFrame) {
        guard let effect = summon else { return }
        let amount = Float(frame.petAmount)
        let origin = effect.ballPosition + SIMD3(0, Float(frame.ballLift), 0)
        var center = origin*(1-amount)+SIMD3<Float>(0, 1.1, 0)*amount
        center.y += 0.18*sin(amount*Float.pi)
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        appearance.simdPosition = center
        appearance.simdScale = SIMD3(repeating: max(0.015, amount))
        appearance.opacity = CGFloat(frame.petOpacity)
        appearance.isHidden = frame.petOpacity < 0.001
        for (material, contents, intensity) in emissions {
            if frame.whiten > 0.001 {
                material.emission.contents = NSColor(white: frame.whiten*1.8, alpha: 1)
                material.emission.intensity = 1
            } else { material.emission.contents = contents; material.emission.intensity = intensity }
        }
        effect.update(frame, petCenter: center)
        SCNTransaction.commit()
    }

    private func completeSummoning() {
        let completion = summonCompletion
        cancelSummoning()
        completion?()
    }
    func cancelSummoning() {
        guard summon != nil else { return }
        summon?.node.removeFromParentNode(); summon = nil; summonCompletion = nil; summonPreview = false
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        appearance.position = SCNVector3(0, 1.1, 0); appearance.scale = SCNVector3(1, 1, 1)
        appearance.opacity = 1; appearance.isHidden = false
        for (material, contents, intensity) in emissions {
            material.emission.contents = contents; material.emission.intensity = intensity
        }
        emissions.removeAll(); SCNTransaction.commit()
        onSummonChanged?()
    }
    func finishSummoningImmediately() {
        // A recall may start its release in the completion; both must settle.
        for _ in 0..<2 where summon != nil { completeSummoning() }
    }
    func previewSummoning(_ phase: PetSummonPhase, at time: Double) {
        if summon?.phase != phase { startSummoning(phase) }
        summonPreview = true
        applySummoning(PetSummonFrame(phase: phase, time: time))
    }

    var summonRestored: Bool {
        summon == nil && emissions.isEmpty && appearance.opacity == 1 && !appearance.isHidden &&
        appearance.scale.x == 1 && abs(appearance.position.y-1.1) < 0.00001
    }

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

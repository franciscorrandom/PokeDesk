// Native, offscreen companion study. Does not open an app profile or calendar.
// Usage: preview-companion model.glb output-dir [--character eevee] [--clip reposo --time 3]
import AppKit
import SceneKit
import GLTFKit2
import ImageIO
import UniformTypeIdentifiers

func previewError(_ message: String) -> NSError {
    NSError(domain: "PokeDesk.Preview", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2 else {
    throw previewError("Uso: preview-companion modelo.glb carpeta [--character nombre] [--clip gesto --time segundos]")
}
let input = URL(fileURLWithPath: arguments[0])
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
var selectedCharacter: String?
var selectedClip: String?
var selectedTime = 0.0
var argumentIndex = 2
while argumentIndex < arguments.count {
    guard argumentIndex + 1 < arguments.count else { throw previewError("Falta el valor de \(arguments[argumentIndex]).") }
    let value = arguments[argumentIndex + 1]
    switch arguments[argumentIndex] {
    case "--character": selectedCharacter = value.lowercased()
    case "--clip": selectedClip = value
    case "--time":
        guard let time = Double(value), time.isFinite, time >= 0 else { throw previewError("Tiempo inválido.") }
        selectedTime = time
    default: throw previewError("Opción desconocida: \(arguments[argumentIndex])")
    }
    argumentIndex += 2
}
guard selectedTime == 0 || selectedClip != nil else { throw previewError("Usa --clip junto con --time.") }
let knownCharacters = ["arcanine", "mewtwo", "pikachu", "charizard", "lucario", "gengar", "bulbasaur", "dragonite", "eevee"]
if selectedCharacter == nil {
    selectedCharacter = knownCharacters.first { input.lastPathComponent.lowercased().contains($0) }
    // The untouched archive can be named only by its UID; preserve its title.
    if selectedCharacter == nil, let bytes = try? Data(contentsOf: input), bytes.count >= 20 {
        let length = (0..<4).reduce(0) { $0 | Int(bytes[12+$1]) << ($1*8) }
        if length > 0, length <= bytes.count - 20,
           let doc = try? JSONSerialization.jsonObject(with: bytes.subdata(in: 20..<20+length)) as? [String: Any],
           let asset = doc["asset"] as? [String: Any], let extras = asset["extras"] as? [String: Any],
           let title = extras["title"] as? String {
            selectedCharacter = knownCharacters.first { title.lowercased().contains($0) }
        }
    }
}
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var finished = false
var failure: Error?
GLTFAsset.load(with: input, options: [:]) { _, status, asset, error, _ in
    if let error { failure = error; finished = true; return }
    guard status == .complete, let asset else { return }
    defer { finished = true }
    do {
        let source = GLTFSCNSceneSource(asset: asset)
        guard let model = source.defaultScene else { throw previewError("El archivo no tiene escena principal.") }
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let orientation = SCNNode(), placement = SCNNode()
        if selectedCharacter == "charizard" {
            model.rootNode.enumerateChildNodes { node, _ in
                for material in node.geometry?.materials ?? [] where material.name?.hasPrefix("CharizardFlame") == true {
                    material.lightingModel = .constant
                    material.writesToDepthBuffer = false
                    material.blendMode = .alpha
                    material.transparencyMode = .singleLayer
                    material.isDoubleSided = true
                    material.emission.contents = NSColor(srgbRed: 1, green: material.name == "CharizardFlame3" ? 0.25 : 0.65, blue: 0.025, alpha: 1)
                    material.emission.intensity = 0.6
                    var modifiers = material.shaderModifiers ?? [:]
                    modifiers[.fragment] = """
                    #pragma transparent
                    #pragma body
                    float mask = _surface.diffuse.r;
                    float alpha = smoothstep(0.04, 0.30, mask) * mask;
                    float3 fire = mix(float3(1.0, 0.08, 0.005), float3(1.0, \(material.name == "CharizardFlame3" ? "0.45, 0.02" : "0.85, 0.12")), mask);
                    _output.color = float4(fire * alpha, alpha);
                    """
                    material.shaderModifiers = modifiers
                }
            }
        }
        let box = model.rootNode.boundingBox
        let height = box.max.y - box.min.y
        guard height.isFinite, height > 0 else { throw previewError("El modelo no tiene altura válida.") }
        let footprint = hypot(box.max.x - box.min.x, box.max.z - box.min.z)
        let limitFootprint = ["charizard", "dragonite", "eevee"].contains(selectedCharacter ?? "")
        let scale = limitFootprint ? min(2.2 / height, 4.6 / max(0.01, footprint)) : 2.2 / height
        placement.scale = SCNVector3(scale, scale, scale)
        placement.position = SCNVector3(-(box.max.x+box.min.x)*scale/2, -box.min.y*scale, -(box.max.z+box.min.z)*scale/2)
        placement.addChildNode(model.rootNode)
        orientation.addChildNode(placement)
        scene.rootNode.addChildNode(orientation)
        let camera = SCNNode(); camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 34
        camera.camera?.projectionDirection = .vertical
        camera.camera?.zNear = 0.01; camera.camera?.zFar = 100
        camera.position = SCNVector3(3.2, 2.25, 5.4)
        camera.look(at: SCNVector3(0, 1.1, 0))
        scene.rootNode.addChildNode(camera)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient
        ambient.light?.intensity = 550; ambient.light?.color = NSColor.white
        scene.rootNode.addChildNode(ambient)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 700; key.light?.color = NSColor.white
        key.eulerAngles = SCNVector3(-0.6, -0.5, 0)
        scene.rootNode.addChildNode(key)
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene; renderer.pointOfView = camera
        renderer.autoenablesDefaultLighting = false
        renderer.sceneTime = 0
        if let selectedClip {
            guard let original = source.animations.first(where: { $0.name == selectedClip })?.animationPlayer.animation else {
                throw previewError("Gesto ausente: \(selectedClip). Disponibles: \(source.animations.map { $0.name }.joined(separator: ", ")).")
            }
            let animation = original.copy() as! SCNAnimation
            animation.usesSceneTimeBase = true; animation.timeOffset = selectedTime
            animation.repeatCount = 0; animation.fillsForward = true; animation.isRemovedOnCompletion = false
            animation.blendInDuration = 0; animation.blendOutDuration = 0
            let player = SCNAnimationPlayer(animation: animation); player.speed = 0
            model.rootNode.addAnimationPlayer(player, forKey: "preview"); player.play()
        }
        let front = atan2(3.2, 5.4)
        var views = [[String: Any]]()
        for (name, yaw) in [("tres-cuartos", 0.0), ("frente", front), ("perfil", front + Double.pi/2)] {
            orientation.eulerAngles.y = CGFloat(yaw)
            let image = renderer.snapshot(atTime: 0, with: NSSize(width: 720, height: 656), antialiasingMode: .multisampling4X)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw previewError("Falló el render nativo.") }
            let bitmap = NSBitmapImageRep(cgImage: cg)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw previewError("Falló la exportación PNG.") }
            let url = output.appendingPathComponent(name+".png")
            try png.write(to: url)
            var left = bitmap.pixelsWide, top = bitmap.pixelsHigh, right = -1, bottom = -1
            for y in 0..<bitmap.pixelsHigh { for x in 0..<bitmap.pixelsWide {
                if (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.03 {
                    left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
                }
            } }
            guard right > left, bottom > top else { throw previewError("El render está vacío: \(name).") }
            views.append(["view": name, "yaw": yaw, "path": url.path, "pixelBounds": [left, top, right, bottom]])
            print("Vista nativa: \(url.path)")
        }
        let report: [String: Any] = ["model": input.path, "character": selectedCharacter ?? "unknown", "clip": selectedClip ?? "static", "time": selectedTime,
            "joints": asset.skins.first?.joints.count ?? 0, "normalizationScale": scale,
            "cameraPosition": [3.2, 2.25, 5.4], "cameraTarget": [0, 1.1, 0], "views": views]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: output.appendingPathComponent("preview.json"))
    } catch { failure = error }
}
let deadline = Date(timeIntervalSinceNow: 90)
while !finished && Date() < deadline { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02)) }
if let failure { throw failure }
if !finished { throw previewError("Se agotó la espera al cargar el modelo.") }

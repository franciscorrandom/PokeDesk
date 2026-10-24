// Native, offscreen study of the actual baked rig. No app profile or calendar.
import AppKit
import SceneKit
import GLTFKit2
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count >= 3 else { fatalError("Uso: preview-arcanine-gait modelo.glb carpeta") }
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let chase = CommandLine.arguments.contains("--full-chase")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var finished = false
var failure: Error?
GLTFAsset.load(with: input, options: [:]) { _, status, asset, error, _ in
    if let error { failure = error; finished = true; return }
    guard status == .complete, let asset else { return }
    let source = GLTFSCNSceneSource(asset: asset)
    guard let model = source.defaultScene,
          let original = source.animations.first(where: { $0.name == "giro-rapido" })?.animationPlayer.animation
    else { fatalError("Modelo o salto no disponible") }
    let scene = SCNScene()
    scene.background.contents = NSColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1)
    let orientation = SCNNode()
    let placement = SCNNode()
    let box = model.rootNode.boundingBox
    let scale = 2.2 / (box.max.y-box.min.y)
    placement.scale = SCNVector3(scale,scale,scale)
    placement.position = SCNVector3(-(box.max.x+box.min.x)*scale/2,-box.min.y*scale,-(box.max.z+box.min.z)*scale/2)
    placement.addChildNode(model.rootNode)
    orientation.addChildNode(placement); scene.rootNode.addChildNode(orientation)
    let camera = SCNNode(); camera.camera = SCNCamera()
    camera.camera?.fieldOfView = 34; camera.camera?.zNear = 0.01; camera.camera?.zFar = 100
    camera.position = SCNVector3(3.2,2.1,5.4); camera.look(at: SCNVector3(0,1.1,0))
    scene.rootNode.addChildNode(camera)
    let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light?.type = .ambient; ambient.light?.intensity = 550
    scene.rootNode.addChildNode(ambient)
    let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 700
    key.light?.castsShadow = true; key.light?.shadowRadius = 4
    key.light?.shadowColor = NSColor.black.withAlphaComponent(0.16)
    key.light?.shadowMapSize = NSSize(width:2048,height:2048)
    key.eulerAngles = SCNVector3(-0.6,-0.5,0); scene.rootNode.addChildNode(key)
    // A ground plane makes real contacts and elevation visible in the study.
    // It is never added to the floating desktop character.
    let floor = SCNNode(geometry: SCNPlane(width: 14,height: 14))
    floor.geometry?.firstMaterial?.diffuse.contents = NSColor(srgbRed: 0.69,green: 0.72,blue: 0.77,alpha: 1)
    floor.geometry?.firstMaterial?.lightingModel = .lambert
    floor.eulerAngles.x = -.pi/2
    floor.position = SCNVector3(0,-0.006,0)
    scene.rootNode.addChildNode(floor)
    let renderer = SCNRenderer(device: nil,options: nil)
    renderer.scene = scene; renderer.pointOfView = camera; renderer.autoenablesDefaultLighting = false
    renderer.isJitteringEnabled = true
    for (name,yaw) in [("salto-tres-cuartos",Float(0)),("salto-perfil",Float.pi/2)] {
        orientation.eulerAngles.y = CGFloat(yaw)
        let frames = chase ? 200 : 60
        let artifact = chase ? name.replacingOccurrences(of:"salto",with:"giro") : name
        let url = output.appendingPathComponent(artifact+".gif")
        guard let gif = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames,nil) else { fatalError("GIF") }
        CGImageDestinationSetProperties(gif,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
        var jointFrames = [[String:Any]]()
        for frame in 0..<frames {
            autoreleasepool {
                // Preview the one-second bound with a little space before/after.
                let time = (chase ? 0 : 0.18)+Double(frame)/50
                model.rootNode.removeAllAnimations()
                let a = original.copy() as! SCNAnimation
                a.usesSceneTimeBase = true; a.timeOffset = time; a.repeatCount = 0
                a.fillsForward = true; a.isRemovedOnCompletion = false
                a.blendInDuration = 0; a.blendOutDuration = 0
                let player = SCNAnimationPlayer(animation:a); player.speed = 0
                model.rootNode.addAnimationPlayer(player,forKey:"jump"); player.play()
                renderer.sceneTime = 0
                let image = renderer.snapshot(atTime:0,with:NSSize(width:640,height:600),antialiasingMode:.multisampling4X)
                guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { fatalError("Render") }
                CGImageDestinationAddImage(gif,cg,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.02]] as CFDictionary)
                let legs = ["LArm_044","LForeArm_045","LHand_049","RArm_073","RForeArm_074","RHand_078","LThigh_06","LLeg_07","LFoot_08","RThigh_017","RLeg_018","RFoot_019"]
                var sample: [String:Any] = ["time":time]
                for n in legs {
                    if let node = model.rootNode.childNode(withName:n,recursively:true) {
                        let p = node.presentation.simdWorldPosition
                        sample[n] = [p.x,p.y,p.z]
                    }
                }
                jointFrames.append(sample)
                if [20,28,36,43,49,57].contains(frame) {
                    let bitmap = NSBitmapImageRep(cgImage:cg)
                    try? bitmap.representation(using:.png,properties:[:])?.write(to:output.appendingPathComponent("\(artifact)-\(frame).png"))
                }
            }
        }
        guard CGImageDestinationFinalize(gif) else { fatalError("Exportar GIF") }
        try? JSONSerialization.data(withJSONObject:jointFrames,options:[.sortedKeys]).write(to:output.appendingPathComponent(artifact+".joints.json"))
        print("Muestra nativa: \(url.path)")
    }
    finished = true
}
while !finished { RunLoop.main.run(until:Date(timeIntervalSinceNow:0.02)) }
if let failure { throw failure }

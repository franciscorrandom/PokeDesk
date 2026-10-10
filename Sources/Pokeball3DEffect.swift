import AppKit
import SceneKit
import simd

/// Procedural geometry: two hinged shells, inner lining, rim and front button.
/// The luminous geometry has a soft radial alpha shader. Its
/// alpha participates in transparent-window composition, unlike screen bloom.
final class Pokeball3DEffect {
    let node = SCNNode()
    let phase: PetSummonPhase
    private let ball = SCNNode()
    private let lid = SCNNode()
    private let core = SCNNode()
    private let ballHalo = SCNNode()
    private let petHalo = SCNNode()
    private let beam = SCNNode()
    private let beamAura = SCNNode()
    private let light = SCNNode()
    private var sparks: [SCNNode] = []
    let energyColor: NSColor
    private var color: NSColor { energyColor }
    var ballPosition: SIMD3<Float> { phase == .release ? SIMD3(0.68, 0.34, 0.58) : SIMD3(-0.68, 0.34, 0.58) }

    init(phase: PetSummonPhase) {
        self.phase = phase
        energyColor = phase == .release ? NSColor(srgbRed: 0.02, green: 0.32, blue: 1, alpha: 1) : NSColor(srgbRed: 1, green: 0.045, blue: 0.12, alpha: 1)
        node.name = "PokeballTransition"
        node.addChildNode(ball)
        ball.name = "Pokeball3D"
        let radius: Float = 0.27
        let red = Self.material(NSColor(red: 0.80, green: 0.035, blue: 0.06, alpha: 1))
        let white = Self.material(NSColor(white: 0.95, alpha: 1))
        let dark = Self.material(NSColor(white: 0.06, alpha: 1))
        let bottom = SCNNode(geometry: Self.hemisphere(radius: radius, top: false))
        bottom.name = "PokeballLowerShell"; bottom.geometry?.materials = [white]
        ball.addChildNode(bottom)
        lid.name = "PokeballHinge"; lid.position = SCNVector3(0, 0, -Double(radius))
        let cap = SCNNode(geometry: Self.hemisphere(radius: radius, top: true))
        cap.position = SCNVector3(0, 0, Double(radius)); cap.geometry?.materials = [red]
        cap.name = "PokeballUpperShell"; lid.addChildNode(cap)
        let lining = SCNNode(geometry: Self.hemisphere(radius: radius-0.012, top: true, inside: true))
        lining.position = cap.position; lining.geometry?.materials = [white]; lid.addChildNode(lining)
        let upperRim = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(radius-0.006), pipeRadius: 0.014))
        upperRim.position = cap.position; upperRim.geometry?.materials = [dark]; lid.addChildNode(upperRim)
        ball.addChildNode(lid)
        let rim = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(radius-0.008), pipeRadius: 0.025))
        rim.geometry?.materials = [dark]; ball.addChildNode(rim)
        for (r, z, mat) in [(0.075, 0.262, dark), (0.052, 0.285, white)] {
            let button = SCNNode(geometry: SCNCylinder(radius: r, height: 0.018))
            button.eulerAngles.x = .pi/2; button.position.z = z
            button.geometry?.materials = [mat]; ball.addChildNode(button)
        }
        core.geometry = SCNSphere(radius: 0.095); core.geometry?.materials = [Self.luminous(.white)]
        core.position.y = 0.05; ball.addChildNode(core)
        ballHalo.geometry = Self.halo(color); ballHalo.constraints = [SCNBillboardConstraint()]
        petHalo.geometry = Self.halo(color); petHalo.constraints = [SCNBillboardConstraint()]
        ballHalo.renderingOrder = 20; petHalo.renderingOrder = 21
        ballHalo.categoryBitMask = 2; petHalo.categoryBitMask = 2
        node.addChildNode(ballHalo); node.addChildNode(petHalo)
        beam.geometry = SCNCylinder(radius: 0.012, height: 1)
        beam.geometry?.materials = [Self.luminous(.white)]; node.addChildNode(beam)
        beam.categoryBitMask = 2
        beamAura.geometry = SCNCylinder(radius: 0.065, height: 1)
        beamAura.geometry?.materials = [Self.luminous(color.withAlphaComponent(0.75))]; node.addChildNode(beamAura)
        beamAura.geometry?.firstMaterial?.blendMode = .alpha
        beamAura.categoryBitMask = 2
        light.light = SCNLight(); light.light?.type = .omni
        light.light?.color = color; light.light?.attenuationStartDistance = 0; light.light?.attenuationEndDistance = 3
        node.addChildNode(light)
        for i in 0..<26 {
            let spark = SCNNode(geometry: Self.halo(i%3 == 0 ? .white : color))
            spark.constraints = [SCNBillboardConstraint()]; spark.renderingOrder = 22
            spark.categoryBitMask = 2
            node.addChildNode(spark); sparks.append(spark)
        }
    }

    func update(_ frame: PetSummonFrame, petCenter: SIMD3<Float>) {
        let t = frame.progress*phase.duration
        let position = ballPosition + SIMD3(0, Float(frame.ballLift), 0)
        ball.simdPosition = position
        ball.opacity = CGFloat(frame.ballOpacity)
        ball.isHidden = frame.ballOpacity < 0.001
        let arrival = PetSummonFrame.ramp(t, 0, 0.38)
        ball.eulerAngles = SCNVector3(0.10*(1-arrival), 0.53 + (1-arrival)*Double.pi*1.2, 0.08*(1-arrival))
        lid.eulerAngles.x = -frame.lidOpen*1.32
        core.opacity = CGFloat(frame.glow); core.isHidden = frame.glow < 0.001
        core.scale = SCNVector3(repeating: 0.8+frame.glow*0.5)
        ballHalo.simdPosition = position+SIMD3(0, 0.05, 0)
        ballHalo.scale = SCNVector3(repeating: 0.65+frame.glow*0.28)
        ballHalo.opacity = CGFloat(frame.glow*0.95); ballHalo.isHidden = frame.glow < 0.001
        petHalo.simdPosition = petCenter
        petHalo.scale = SCNVector3(repeating: 0.40+frame.petAmount*1.32)
        petHalo.opacity = CGFloat(frame.glow*0.82); petHalo.isHidden = frame.glow < 0.001
        Self.connect(beam, from: position, to: petCenter)
        Self.connect(beamAura, from: position, to: petCenter)
        beam.opacity = CGFloat(frame.beam); beam.isHidden = frame.beam < 0.001
        beamAura.opacity = CGFloat(frame.beam); beamAura.isHidden = frame.beam < 0.001
        light.simdPosition = petCenter; light.light?.intensity = CGFloat(frame.glow*420)
        for (i, spark) in sparks.enumerated() {
            let offset = Double(i)*0.037
            let age = (t-(phase == .release ? 0.78 : 0.40)-offset)/1.1
            let live = age > 0 && age < 1
            spark.isHidden = !live || frame.sparks < 0.001
            guard live else { continue }
            let angle = Double(i)*2.399963
            let height = Double(i%7)/6*1.7-0.65
            let center = phase == .release ? SIMD3<Float>(0, 1.08, 0) : position
            let radius = phase == .release ? 0.20+age*0.80 : 0.78*(1-age)
            spark.simdPosition = center + SIMD3(Float(cos(angle)*radius), Float(height*(phase == .release ? age : 1-age)), Float(sin(angle)*radius*0.55))
            let s = (i%4 == 0 ? 0.095 : 0.052)*(0.70+0.30*sin(age*Double.pi))
            spark.scale = SCNVector3(repeating: s)
            spark.opacity = CGFloat(frame.sparks*sin(age*Double.pi)*0.9)
        }
    }

    private static func material(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = color; m.roughness.contents = 0.24; m.metalness.contents = 0.18
        return m
    }
    private static func luminous(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .constant; m.diffuse.contents = color
        m.blendMode = .add; m.isDoubleSided = true; m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false; m.transparencyMode = .singleLayer
        return m
    }
    private static func connect(_ node: SCNNode, from a: SIMD3<Float>, to b: SIMD3<Float>) {
        let delta = b-a; let distance = simd_length(delta)
        node.simdPosition = (a+b)*0.5
        node.simdScale = SIMD3(1, max(0.001, distance), 1)
        if distance > 0.001 { node.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: delta/distance) }
    }
    private static func hemisphere(radius: Float, top: Bool, inside: Bool = false) -> SCNGeometry {
        let rings = 20, segments = 64
        var points = [SCNVector3](), normals = [SCNVector3](), indices = [Int32]()
        for row in 0...rings {
            let phi = Double(row)/Double(rings)*Double.pi/2 + (top ? 0 : Double.pi/2)
            for column in 0...segments {
                let theta = Double(column)/Double(segments)*Double.pi*2
                let normal = SCNVector3(sin(phi)*cos(theta), cos(phi), sin(phi)*sin(theta))
                points.append(SCNVector3(normal.x*CGFloat(radius), normal.y*CGFloat(radius), normal.z*CGFloat(radius)))
                normals.append(inside ? SCNVector3(-normal.x, -normal.y, -normal.z) : normal)
            }
        }
        for row in 0..<rings { for col in 0..<segments {
            let a = Int32(row*(segments+1)+col), b = a+Int32(segments+1)
            let triangle: [Int32] = [a, b, a+1, a+1, b, b+1]
            indices += inside ? triangle : [triangle[0], triangle[2], triangle[1], triangle[3], triangle[5], triangle[4]]
        }}
        return SCNGeometry(sources: [SCNGeometrySource(vertices: points), SCNGeometrySource(normals: normals)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    }
    private static func halo(_ tint: NSColor) -> SCNGeometry {
        let geometry = SCNPlane(width: 2, height: 2)
        let material = luminous(tint)
        // A saturated alpha corona remains visible over a white desktop.
        // The white center and core retain the impression of brilliant light.
        material.blendMode = .alpha
        material.shaderModifiers = [.fragment: """
        #pragma transparent
        #pragma body
        float radius = length(_surface.diffuseTexcoord - float2(0.5)) * 2.0;
        float falloff = exp(-radius * radius * 3.2) * pow(max(0.0, 1.0 - radius), 0.8);
        float alpha = _output.color.a * falloff;
        float whiteCore = exp(-radius * radius * 90.0);
        float3 glow = mix(_output.color.rgb, float3(1.0), whiteCore * 0.9);
        _output.color = float4(glow * alpha, alpha);
        """]
        geometry.materials = [material]
        return geometry
    }
}

private extension SCNVector3 {
    init(repeating value: Double) { self.init(value, value, value) }
}

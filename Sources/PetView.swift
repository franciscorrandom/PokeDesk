import AppKit
import SceneKit
import SwiftUI

private final class PetSceneView: SCNView {
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class PetTimerBadge: NSView {
    var focusTimer: FocusTimer?
    var character: PetCharacter = .arcanine
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    var badgeRect: NSRect {
        let width = min(130, bounds.width - 20)
        return NSRect(x: (bounds.width - width) / 2, y: 2, width: width, height: 23)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill(using: .copy)
        guard let focus = focusTimer, focus.showsOnFace(at: Date()) else { return }
        let rect = badgeRect
        let path = NSBezierPath(roundedRect: rect, xRadius: 9, yRadius: 9)
        let theme = PetTheme(character: character)
        NSColor(theme.paper).withAlphaComponent(0.98).setFill(); path.fill()
        let color = NSColor(theme.red)
        color.withAlphaComponent(0.55).setStroke(); path.lineWidth = 0.8; path.stroke()
        let label = (focus.phase == .paused ? "Ⅱ " : "◷ ") + focus.display(at: Date())
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold), .foregroundColor: color]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2 + 1), withAttributes: attributes)
        let progress = NSRect(x: rect.minX + 10, y: rect.minY + 2, width: (rect.width - 20) * focus.progress(at: Date()), height: 1)
        color.withAlphaComponent(0.7).setFill(); NSBezierPath(roundedRect: progress, xRadius: 1, yRadius: 1).fill()
    }
}

final class PetView: NSView {
    let image: NSImage
    let engine = Arcanine3DScene()
    private let sceneView: PetSceneView
    private let badge = PetTimerBadge()
    var animate = true { didSet { engine.effectsEnabled = animate && summoningEnabled } }
    var summoningEnabled = true { didSet { engine.effectsEnabled = animate && summoningEnabled } }
    var focusing = false
    var alerting = false
    var focusTimer: FocusTimer? { didSet { badge.focusTimer = focusTimer; badge.needsDisplay = true } }
    var character: PetCharacter = .arcanine { didSet { badge.character = character; badge.needsDisplay = true } }
    var speaking = false
    var onReady: (() -> Void)?
    var onError: ((String) -> Void)?
    var onClick: (() -> Void)?
    var onContextMenu: ((NSEvent) -> Void)?
    var onDrag: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onRotationEnd: ((Double) -> Void)?
    var onPettingRequested: (() -> Void)?
    private var motion = Arcanine3DMotion()
    private var renderedRevision = -1
    private var previewing = false
    private var initialMouse = NSPoint.zero
    private var initialOrigin = NSPoint.zero
    private var initialYaw = 0.0
    private var rotating = false
    private var rotationBlocked = false
    private var petting = false
    private var pettedDuringDrag = false
    private(set) var dragging = false
    private var moved = false
    var currentClip: ArcanineClip { motion.clip }
    var animationRevision: Int { motion.revision }
    var yaw: Double { engine.yaw }

    init(image: NSImage, frame: NSRect) {
        self.image = image
        sceneView = PetSceneView(frame: .zero, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        super.init(frame: frame)
        wantsLayer = true; layer?.isOpaque = false; layer?.backgroundColor = NSColor.clear.cgColor
        sceneView.backgroundColor = .clear
        sceneView.wantsLayer = true; sceneView.layer?.isOpaque = false
        sceneView.scene = engine.scene; sceneView.pointOfView = engine.camera
        sceneView.antialiasingMode = .multisampling4X
        sceneView.preferredFramesPerSecond = 30
        sceneView.allowsCameraControl = false
        sceneView.isPlaying = true
        addSubview(sceneView); addSubview(badge)
        // Start the short light sequence only after SceneKit has uploaded its
        // geometry, textures and materials. A cold renderer must not consume it.
        engine.prepareSummon = { [weak self] node, begin in
            guard let self else { return }
            self.sceneView.prepare([node]) { _ in DispatchQueue.main.async { begin() } }
        }
        engine.onReady = { [weak self] in
            guard let self else { return }
            self.motion = Arcanine3DMotion(character: self.engine.character)
            self.previewing = false; self.renderedRevision = -1
            self.setAccessibilityLabel("\(self.engine.character.name) 3D. Haz clic para abrir los accesos rápidos; arrastra para mover; Option y arrastra para girar; Mayús y arrastra para acariciar.")
            self.play(self.alerting ? .alert : .greeting); self.tickMotion(); self.onReady?()
        }
        engine.onError = { [weak self] message in self?.needsDisplay = true; self?.onError?(message) }
        engine.onSummonChanged = { [weak self] in
            guard let self else { return }
            if !self.engine.isTransitioning {
                self.motion = Arcanine3DMotion(character: self.engine.character)
                self.renderedRevision = -1
            }
            self.sceneView.needsDisplay = true
        }
        setAccessibilityElement(true)
        toolTip = "Arrastra para mover · ⌥ Option + arrastra para girar · ⇧ Mayús + arrastra para acariciar"
        setAccessibilityLabel("Arcanine 3D, tu compañero de escritorio. Haz clic para abrir los accesos rápidos semicirculares; arrastra para moverlo; mantén Option y arrastra para girarlo horizontalmente; mantén Mayús y arrastra para acariciarlo.")
        setAccessibilityHelp(toolTip)
        setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) no disponible") }
    override var isOpaque: Bool { false }
    override func layout() {
        super.layout()
        sceneView.frame = NSRect(x: 0, y: 28, width: bounds.width, height: max(1, bounds.height - 28))
        badge.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 28)
    }
    func loadModel(character: PetCharacter = .arcanine) {
        engine.effectsEnabled = animate && summoningEnabled
        engine.load(character: character)
    }
    @discardableResult func replaySummoning() -> Bool {
        guard animate, summoningEnabled else { return false }
        previewing = false
        let started = engine.replaySummoning()
        tickMotion()
        return started
    }
    func setYaw(_ angle: Double) { engine.setYaw(angle); sceneView.needsDisplay = true }
    func tickMotion() {
        if !previewing { engine.updateSummoning(at: ProcessInfo.processInfo.systemUptime) }
        if engine.isTransitioning {
            sceneView.isPlaying = !previewing && animate && window?.isVisible == true
            return
        }
        guard engine.ready, !previewing else { return }
        let now = ProcessInfo.processInfo.systemUptime
        motion.focusing = focusing; motion.alerting = alerting
        motion.setEnabled(animate, at: now)
        motion.tick(at: now)
        if renderedRevision != motion.revision {
            renderedRevision = motion.revision
            if animate { engine.play(motion.clip) } else { engine.rest() }
        }
        // Pause rendering with the hidden pet and when macOS requests reduced motion.
        sceneView.isPlaying = animate && window?.isVisible == true
    }
    func play(_ clip: ArcanineClip, manual: Bool = false) {
        motion.focusing = focusing; motion.alerting = alerting
        motion.setEnabled(animate, at: ProcessInfo.processInfo.systemUptime)
        motion.request(clip, at: ProcessInfo.processInfo.systemUptime, manual: manual)
        tickMotion()
    }
    func react() {
        motion.focusing = focusing; motion.alerting = alerting
        motion.setEnabled(animate, at: ProcessInfo.processInfo.systemUptime)
        motion.click(at: ProcessInfo.processInfo.systemUptime); tickMotion()
    }

    func preview(_ clip: ArcanineClip, at time: TimeInterval) {
        previewing = true; sceneView.isPlaying = false
        sceneView.sceneTime = 0
        engine.play(clip, preview: true, previewTime: time)
    }
    func previewSummoning(_ phase: PetSummonPhase, at time: Double) {
        preview(.idle, at: 0)
        engine.previewSummoning(phase, at: time)
        sceneView.needsDisplay = true
    }
    func snapshot() -> NSImage {
        layoutSubtreeIfNeeded()
        let rendered = sceneView.snapshot()
        let result = NSImage(size: bounds.size)
        result.lockFocus()
        rendered.draw(in: sceneView.frame)
        if let bitmap = badge.bitmapImageRepForCachingDisplay(in: badge.bounds) {
            badge.cacheDisplay(in: badge.bounds, to: bitmap)
            if let cg = bitmap.cgImage { NSImage(cgImage: cg, size: badge.bounds.size).draw(in: badge.frame) }
        }
        result.unlockFocus()
        return result
    }
    func node(_ name: String) -> SCNNode? { engine.node(name) }

    func containsPet(_ point: NSPoint) -> Bool {
        if focusTimer?.showsOnFace(at: Date()) == true && badge.badgeRect.contains(point) { return true }
        guard engine.ready || engine.isTransitioning else { return false }
        let p = sceneView.convert(point, from: self)
        guard sceneView.bounds.contains(p) else { return false }
        return !sceneView.hitTest(p, options: [.boundingBoxOnly: false, .ignoreHiddenNodes: true, .categoryBitMask: 1]).isEmpty
    }
    override func hitTest(_ point: NSPoint) -> NSView? { containsPet(point) ? self : nil }
    private func mousePosition(_ event: NSEvent) -> NSPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
    }
    override func mouseDown(with event: NSEvent) {
        initialMouse = mousePosition(event); initialOrigin = window?.frame.origin ?? .zero
        initialYaw = yaw
        // Lock the gesture at mouse-down: releasing Option mid-drag never moves the panel.
        rotating = event.modifierFlags.contains(.option)
        rotationBlocked = rotating && engine.isTransitioning
        petting = !rotating && event.modifierFlags.contains(.shift)
        pettedDuringDrag = false
        dragging = true; moved = false
    }
    override func mouseDragged(with event: NSEvent) {
        let point = mousePosition(event)
        let delta = NSPoint(x: point.x - initialMouse.x, y: point.y - initialMouse.y)
        if petting {
            if !pettedDuringDrag && abs(delta.x) + abs(delta.y) > 4 {
                pettedDuringDrag = true
                // One response per stroke: mouse events never restart the animation every frame.
                onPettingRequested?()
            }
            return
        }
        if rotating {
            guard !rotationBlocked && !engine.isTransitioning else { rotationBlocked = true; return }
            if abs(delta.x) > 4 { moved = true }
            if moved { setYaw(PetRotation.dragged(from: initialYaw, horizontalPoints: delta.x)) }
            return
        }
        if abs(delta.x) + abs(delta.y) > 4 { moved = true }
        if moved {
            window?.setFrameOrigin(NSPoint(x: initialOrigin.x + delta.x, y: initialOrigin.y + delta.y)); onDrag?()
        }
    }
    override func mouseUp(with event: NSEvent) {
        dragging = false
        if petting {
            petting = false
            if !pettedDuringDrag { onPettingRequested?() }
            return
        }
        if rotating {
            rotating = false
            if moved && !rotationBlocked { onRotationEnd?(yaw) }
        } else if moved { onDragEnd?() } else { react(); onClick?() }
    }
    override func rightMouseDown(with event: NSEvent) { react(); onContextMenu?(event) }
    override func accessibilityPerformPress() -> Bool { react(); onClick?(); return true }
}

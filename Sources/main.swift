import AppKit
import SwiftUI
import Combine
import ImageIO
import UniformTypeIdentifiers
import simd
import SceneKit

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    var onEscape: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let thumbnailTest = CommandLine.arguments.contains("--thumbnail-test")
    private var hiddenIncomingChecks = [Bool]()
    private let rosterTest = CommandLine.arguments.contains("--roster-smoke-test")
    private let characterTest = CommandLine.arguments.contains("--characters-smoke-test")
    private let pokeballTest = CommandLine.arguments.contains("--pokeball-smoke-test")
    private let smokeTest = CommandLine.arguments.contains("--thumbnail-test") || CommandLine.arguments.contains("--roster-smoke-test") || CommandLine.arguments.contains("--smoke-test") || CommandLine.arguments.contains("--characters-smoke-test") || CommandLine.arguments.contains("--pokeball-smoke-test")
    private var smokeStarted = false
    private var characterReady: (() -> Void)?
    private var pokeballReady: (() -> Void)?
    private var summonPhases = [String]()
    private var recordSummons = true
    private var cancelRecall = false
    private var cancelIncoming = false
    private lazy var model = PetModel(storageURL: smokeTest ? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(thumbnailTest ? "pokedesk-thumbnail-smoke/estado.json" : rosterTest ? "pokedesk-roster-smoke/estado.json" : pokeballTest ? "arcanine-pokeball-smoke/estado.json" : characterTest ? "arcanine-characters-smoke/estado.json" : "arcanine-ical-smoke/estado.json") : nil)
    private var petPanel: PetPanel!
    private var petView: PetView!
    private var dashboard: BubblePanel?
    private var quickMenu: BubblePanel?
    private var quickDetail: BubblePanel?
    private var quickHostingView: PetQuickHostingView?
    private let quickState = PetQuickMenuState()
    private var bubblePanel: BubblePanel!
    private var statusItem: NSStatusItem!
    private var renderTimer: Timer?
    private var alertSubscription: AnyCancellable?
    private var tabSubscription: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var menu = NSMenu()
    private var lastFaceTime = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if thumbnailTest || characterTest || pokeballTest || rosterTest { model.settings.petCharacter = "arcanine" }
        if pokeballTest { model.settings.motionEnabled = true; model.settings.soundEnabled = false }
        guard let image = NSImage(named: "arcanine") else {
            let alert = NSAlert()
            alert.messageText = "No encontré la imagen de Arcanine"
            alert.informativeText = "Vuelve a descargar el ZIP completo de PokéDesk."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let size = panelSize()
        petPanel = PetPanel(contentRect: NSRect(origin: initialPosition(size: size), size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        petPanel.title = "PokéDesk — compañero"
        petPanel.backgroundColor = .clear
        petPanel.isOpaque = false
        petPanel.hasShadow = false
        petPanel.level = .floating
        petPanel.hidesOnDeactivate = false
        petPanel.isReleasedWhenClosed = false
        petPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        petPanel.animationBehavior = .none
        petView = PetView(image: image, frame: NSRect(origin: .zero, size: size))
        petView.summoningEnabled = !smokeTest || pokeballTest
        if pokeballTest {
            let prepare = petView.engine.prepareSummon
            petView.engine.prepareSummon = { [weak self] node, begin in
                guard let self else { return }
                if self.petView.engine.summoningPhase == .release {
                    self.hiddenIncomingChecks.append(self.petView.engine.incomingHidden)
                    // Simulate a slow GPU preparation: the new mesh must stay hidden.
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.12) {
                        self.hiddenIncomingChecks.append(self.petView.engine.incomingHidden)
                        prepare?(node, begin)
                    }
                } else { prepare?(node, begin) }
            }
            petView.engine.onSummonStarted = { [weak self] phase in
                guard let self, self.recordSummons else { return }
                self.summonPhases.append(phase.rawValue)
                if phase == .recall && self.cancelRecall {
                    self.cancelRecall = false
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.75) { _ = self.model.selectCharacter(.arcanine) }
                }
                if phase == .release && self.cancelIncoming {
                    self.cancelIncoming = false
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.8) { _ = self.model.selectCharacter(.arcanine) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now()+0.95) {
                    self.capturePreview(self.petView, name: "pokeball-live-\(phase.rawValue)")
                }
            }
        }
        petView.autoresizingMask = [.width, .height]
        petView.onClick = { [weak self] in self?.toggleQuickMenu() }
        petView.onPettingRequested = { [weak self] in self?.model.requestAnimation(.petting) }
        petView.onContextMenu = { [weak self] _ in self?.toggleQuickMenu() }
        petView.onDrag = { [weak self] in self?.positionBubble(); self?.positionDashboard(); self?.positionQuickMenu() }
        petView.onDragEnd = { [weak self] in self?.savePosition() }
        petView.onRotationEnd = { [weak self] angle in
            self?.model.settings.setCharacterYaw(angle)
            self?.model.save()
        }
        petPanel.contentView = petView
        petPanel.orderFrontRegardless()
        bubblePanel = BubblePanel(contentRect: NSRect(x: 0, y: 0, width: 350, height: 320), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bubblePanel.title = "PokéDesk — aviso"
        bubblePanel.backgroundColor = .clear
        bubblePanel.isOpaque = false
        bubblePanel.hasShadow = true
        bubblePanel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        bubblePanel.hidesOnDeactivate = false
        bubblePanel.isReleasedWhenClosed = false
        bubblePanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        bubblePanel.contentView = NSHostingView(rootView: AlertBubbleView(model: model))
        bubblePanel.onEscape = { [weak self] in self?.model.dismissAlert() }
        alertSubscription = model.$currentAlert.sink { [weak self] alert in
            DispatchQueue.main.async {
                guard let self else { return }
                if alert != nil { self.closeQuickMenu(restoreAlert: false); self.dashboard?.orderOut(nil); self.positionBubble(); self.bubblePanel.orderFrontRegardless(); self.petView.alerting = true; self.petView.play(alert?.focusTimerID != nil ? .celebration : .alert) }
                else { self.petView.alerting = false; self.bubblePanel.orderOut(nil) }
            }
        }
        tabSubscription = model.$dashboardTab.sink { [weak self] _ in DispatchQueue.main.async { self?.positionDashboard() } }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.closeDashboard(); self?.closeQuickMenu() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.window != self.dashboard, event.window != self.quickMenu,
               event.window != self.quickDetail, event.window != self.petPanel, event.window != self.bubblePanel {
                self.closeDashboard(); self.closeQuickMenu()
            }
            return event
        }
        model.onSettingsChanged = { [weak self] in self?.applySettings() }
        model.onTaskCompleted = { [weak self] in self?.petView.play(.celebration) }
        model.onFocusStarted = { [weak self] in self?.petView.play(.curious) }
        model.onPokeballRequested = { [weak self] in self?.replayPokeball() }
        model.onAnimationRequested = { [weak self] clip in self?.petView.play(clip, manual: true) }
        petView.onError = { [weak self] message in
            guard let self else { return }
            self.model.errorMessage = message
            if self.petView.engine.ready {
                self.model.settings.petCharacter = self.petView.engine.character.rawValue
                self.model.save()
            }
            if self.smokeTest {
                let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("smoke-test.json")
                try? JSONSerialization.data(withJSONObject: ["model3DLoaded": false, "error": message]).write(to: url)
                NSApp.terminate(nil)
            } else {
                let alert = NSAlert(); alert.messageText = "No pude abrir el compañero 3D"
                alert.informativeText = message; alert.runModal()
            }
        }
        petView.onReady = { [weak self] in
            guard let self, self.smokeTest else { return }
            if self.pokeballTest, let next = self.pokeballReady { next(); return }
            if (self.thumbnailTest || self.characterTest || self.rosterTest), let next = self.characterReady { next(); return }
            guard !self.smokeStarted else { return }
            self.smokeStarted = true
            if self.thumbnailTest { self.performThumbnailTest() }
            else if self.pokeballTest { self.performPokeballTest() }
            else if self.rosterTest { self.performRosterTest() }
            else if self.characterTest { self.performCharacterTest() } else { self.performSmokeTest() }
        }
        setupMenu()
        applySettings()
        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in DispatchQueue.main.async { self?.renderTick() } }
        RunLoop.main.add(renderTimer!, forMode: .common)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in DispatchQueue.main.async { self?.savePosition() } }
        petView.loadModel(character: model.settings.character)
        if !smokeTest {
            model.start()
            if model.feeds.isEmpty { model.dashboardTab = 3; showDashboard() }
        }
    }

    private func panelSize() -> NSSize { NSSize(width: model.settings.petSize * 1.6, height: model.settings.petSize * 1.3 + 28) }
    private func initialPosition(size: NSSize) -> NSPoint {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let fallback = NSPoint(x: screen.maxX - size.width - 35, y: screen.minY + 28)
        if let x = model.settings.positionX, let y = model.settings.positionY {
            return clamped(NSRect(origin: NSPoint(x: x, y: y), size: size)).origin
        }
        return fallback
    }

    private func clamped(_ rect: NSRect) -> NSRect {
        let screen = NSScreen.screens.max { a, b in
            let ai = a.visibleFrame.intersection(rect)
            let bi = b.visibleFrame.intersection(rect)
            return (ai.isNull ? 0 : ai.width * ai.height) < (bi.isNull ? 0 : bi.width * bi.height)
        } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return rect }
        return NSRect(x: min(max(rect.minX, visible.minX), visible.maxX - rect.width),
                      y: min(max(rect.minY, visible.minY), visible.maxY - rect.height), width: rect.width, height: rect.height)
    }
    private func savePosition() {
        petPanel.setFrame(clamped(petPanel.frame), display: true)
        model.settings.positionX = petPanel.frame.origin.x
        model.settings.positionY = petPanel.frame.origin.y
        model.save()
        positionBubble()
        positionDashboard()
        positionQuickMenu()
    }
    private func applySettings() {
        guard petPanel != nil else { return }
        quickState.character = model.settings.character
        petView.character = model.settings.character
        petView.animate = model.settings.motionEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        petView.loadModel(character: model.settings.character)
        petPanel.title = "\(model.settings.character.name) — mascota"
        petPanel.setContentSize(panelSize())
        petPanel.setFrame(clamped(petPanel.frame), display: true)
        petView.setYaw(model.settings.characterYaw)
        petView.focusing = model.settings.focusTimer?.phase == .running
        petView.tickMotion()
        petView.focusTimer = model.settings.focusTimer.flatMap { $0.showsOnFace(at: Date()) ? $0 : nil }
        petView.needsDisplay = true
        positionBubble()
        positionDashboard()
        positionQuickMenu()
    }

    private func renderTick() {
        petView.focusing = model.settings.focusTimer?.phase == .running
        petView.focusTimer = model.settings.focusTimer.flatMap { $0.showsOnFace(at: Date()) ? $0 : nil }
        if petView.speaking != model.speaking { petView.speaking = model.speaking; petView.needsDisplay = true }
        if model.speaking { petView.needsDisplay = true }
        let time = petView.focusTimer?.display(at: Date()) ?? ""
        if time != lastFaceTime {
            lastFaceTime = time
            petView.needsDisplay = true
            petView.setAccessibilityValue(time.isEmpty ? "" : "Concentración: \(time)")
        }
        let animate = model.settings.motionEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if petView.animate != animate { petView.animate = animate; petView.needsDisplay = true }
        petView.tickMotion()
        if !petView.dragging {
            let mouseInWindow = petPanel.convertPoint(fromScreen: NSEvent.mouseLocation)
            petPanel.ignoresMouseEvents = !petView.containsPet(mouseInWindow)
        }
        if let quickMenu, quickMenu.isVisible, let quickHostingView {
            let point = quickHostingView.convert(quickMenu.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
            quickMenu.ignoresMouseEvents = !quickHostingView.containsControl(point)
        }
    }

    private func positionBubble() {
        guard petPanel != nil, bubblePanel != nil else { return }
        positionFloatingPanel(bubblePanel, width: 350, height: 320)
    }

    private func positionDashboard() {
        guard let dashboard else { return }
        positionFloatingPanel(dashboard, width: 430, height: model.dashboardTab == -1 ? 620 : model.dashboardTab == 5 ? 760 : 640)
    }

    private func positionQuickMenu() {
        guard let quickMenu else { return }
        let screen = petPanel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let bounds = FloatingRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height)
        let rect = QuickMenuLayout.place(anchorX: petPanel.frame.midX,
            anchorY: petPanel.frame.minY + 28 + (petPanel.frame.height - 28) * 0.82, screen: bounds)
        quickMenu.setFrame(NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height), display: true)
        if let quickDetail, let action = quickState.selected {
            let detail = QuickMenuLayout.detail(width: 350, height: action.detailHeight, menu: rect, screen: bounds)
            quickDetail.setFrame(NSRect(x: detail.x, y: detail.y, width: detail.width, height: detail.height), display: true)
        }
    }

    private func positionFloatingPanel(_ panel: NSPanel, width: Double, height: Double) {
        let pet = petPanel.frame
        let screen = petPanel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? pet
        let rect = FloatingLayout.place(width: width, height: height,
            pet: FloatingRect(x: pet.minX, y: pet.minY, width: pet.width, height: pet.height),
            screen: FloatingRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height))
        panel.setFrame(NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height), display: true)
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Arcanine")
        statusItem.button?.toolTip = "PokéDesk · tu compañero de escritorio"
        menu.delegate = self
        statusItem.menu = menu
        updateMenu()
    }
    func menuWillOpen(_ menu: NSMenu) { updateMenu() }
    private func updateMenu() {
        menu.removeAllItems()
        addMenu("PokéDesk · \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")", action: nil).isEnabled = false
        menu.addItem(.separator())
        addMenu("Abrir menú de PokéDesk", action: #selector(showHome))
        let companions = addMenu("Cambiar Pokémon", action: nil)
        let companionMenu = NSMenu()
        for character in PetCharacter.allCases {
            let item = NSMenuItem(title: character.name, action: #selector(changeCompanion(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = character.rawValue
            item.state = model.settings.character == character ? .on : .off
            item.isEnabled = character.isAvailable(); companionMenu.addItem(item)
        }
        companions.submenu = companionMenu
        addMenu("Repetir salida de la Pokébola", action: #selector(replayPokeball)).isEnabled = petView.animate && !petView.engine.isTransitioning
        let timers = addMenu("Timer de concentración", action: nil)
        let timerMenu = NSMenu()
        for minutes in [5, 10, 30] {
            let item = NSMenuItem(title: "\(minutes) minutos", action: #selector(startQuickTimer(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = minutes
            timerMenu.addItem(item)
        }
        let custom = NSMenuItem(title: "Otro tiempo…", action: #selector(showFocus), keyEquivalent: "")
        custom.target = self
        timerMenu.addItem(custom)
        timers.submenu = timerMenu
        if let focus = model.settings.focusTimer {
            addMenu(focus.phase == .finished ? "Foco completado" : "Concentración · \(focus.display(at: Date()))", action: #selector(showFocus))
            if focus.phase != .finished {
                addMenu(focus.phase == .paused ? "Reanudar timer" : "Pausar timer", action: #selector(toggleFocus))
            }
            addMenu("Cancelar timer", action: #selector(stopFocus))
        }
        let gestures = addMenu("Animaciones 3D", action: nil)
        let gestureMenu = NSMenu()
        for clip in model.settings.character.clips {
            let item = NSMenuItem(title: model.settings.character.title(for: clip), action: #selector(playGesture(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = clip.rawValue; gestureMenu.addItem(item)
        }
        gestures.submenu = gestureMenu
        addMenu("Restablecer vista", action: #selector(resetView))
        addMenu("Probar un recordatorio", action: #selector(testReminder))
        addMenu(petPanel.isVisible ? "Ocultar mascota" : "Mostrar mascota", action: #selector(togglePet))
        addMenu("Volver a la esquina", action: #selector(resetPosition))
        addMenu(model.settings.pausedUntil.map({ $0 > Date() }) == true ? "Reanudar avisos" : "Pausar avisos 1 hora", action: #selector(pauseReminders))
        menu.addItem(.separator())
        addMenu("Salir de PokéDesk", action: #selector(quit), key: "q")
    }
    @discardableResult private func addMenu(_ title: String, action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }
    @objc private func showDashboard() {
        closeQuickMenu(restoreAlert: false)
        if dashboard == nil {
            let window = BubblePanel(contentRect: NSRect(x: 0, y: 0, width: 430, height: 415), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "PokéDesk · menú flotante"
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            window.hidesOnDeactivate = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.animationBehavior = .none
            window.onEscape = { [weak self] in self?.closeDashboard() }
            window.contentView = NSHostingView(rootView: DashboardView(model: model, onClose: { [weak self] in self?.closeDashboard() }))
            window.appearance = NSAppearance(named: .aqua)
            dashboard = window
        }
        model.refreshCalendar()
        positionDashboard()
        bubblePanel.orderOut(nil)
        dashboard?.makeKeyAndOrderFront(nil)
    }
    @objc private func showHome() { model.dashboardTab = -1; showDashboard() }
    private func toggleQuickMenu() {
        if quickMenu?.isVisible == true { closeQuickMenu() }
        else { closeDashboard(); showQuickMenu() }
    }
    private func makeQuickPanel(title: String, width: Double, height: Double) -> BubblePanel {
        let panel = BubblePanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = title; panel.backgroundColor = .clear; panel.isOpaque = false
        panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.animationBehavior = .none; panel.appearance = NSAppearance(named: .aqua)
        panel.onEscape = { [weak self] in self?.closeQuickMenu() }
        return panel
    }
    private func showQuickMenu() {
        if quickMenu == nil {
            let panel = makeQuickPanel(title: "PokéDesk · accesos rápidos", width: QuickMenuLayout.width, height: QuickMenuLayout.height)
            panel.hasShadow = false
            let host = PetQuickHostingView(rootView: PetQuickMenuView(state: quickState,
                onSelect: { [weak self] in self?.selectQuickAction($0) },
                onClose: { [weak self] in self?.closeQuickMenu() }))
            host.wantsLayer = true; host.layer?.isOpaque = false; host.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = host; quickMenu = panel; quickHostingView = host
        }
        quickState.selected = nil
        quickDetail?.orderOut(nil)
        positionQuickMenu()
        bubblePanel.orderOut(nil)
        quickMenu?.ignoresMouseEvents = false
        quickMenu?.makeKeyAndOrderFront(nil)
    }
    private func selectQuickAction(_ action: PetQuickAction) {
        if action == .petting {
            runQuickAnimation(.petting)
            return
        }
        if action == .openPanel { showHome(); return }
        if quickState.selected == action {
            quickState.selected = nil; quickDetail?.orderOut(nil); quickMenu?.makeKeyAndOrderFront(nil)
            return
        }
        quickState.selected = action
        if quickDetail == nil {
            quickDetail = makeQuickPanel(title: "PokéDesk · vista rápida", width: 350, height: action.detailHeight)
            quickDetail?.hasShadow = true
        }
        quickDetail?.title = "PokéDesk · \(action.title) rápida"
        quickDetail?.contentView = NSHostingView(rootView: PetQuickDetailView(model: model, action: action,
            onExpand: { [weak self] in self?.model.dashboardTab = action.tab ?? -1; self?.showDashboard() },
            onClose: { [weak self] in self?.quickDetail?.orderOut(nil); self?.quickState.selected = nil; self?.quickMenu?.makeKeyAndOrderFront(nil) },
            onTimer: { [weak self] in self?.runQuickTimer($0) },
            onAnimation: { [weak self] in self?.runQuickAnimation($0) },
            onCharacter: { [weak self] character in self?.closeQuickMenu(restoreAlert: false); _ = self?.model.selectCharacter(character) }))
        if action == .agenda { model.refreshCalendar() }
        positionQuickMenu()
        quickDetail?.makeKeyAndOrderFront(nil)
    }
    private func runQuickTimer(_ minutes: Int) { model.startFocus(minutes: minutes); closeQuickMenu() }
    private func runQuickAnimation(_ clip: ArcanineClip) {
        closeQuickMenu()
        let revision = petView.animationRevision
        model.requestAnimation(clip)
        if petView.animationRevision == revision && model.errorMessage != nil { showHome() }
    }
    private func closeQuickMenu(restoreAlert: Bool = true) {
        let wasVisible = quickMenu?.isVisible == true || quickDetail?.isVisible == true
        quickMenu?.orderOut(nil); quickDetail?.orderOut(nil); quickState.selected = nil
        if wasVisible && restoreAlert && dashboard?.isVisible != true && model.currentAlert != nil {
            positionBubble(); bubblePanel.orderFrontRegardless()
        }
    }
    private func closeDashboard() {
        guard dashboard?.isVisible == true else { return }
        dashboard?.orderOut(nil)
        if model.currentAlert != nil { positionBubble(); bubblePanel.orderFrontRegardless() }
    }
    @objc private func playGesture(_ item: NSMenuItem) {
        if let id = item.representedObject as? String, let clip = ArcanineClip(rawValue: id) { model.requestAnimation(clip) }
    }
    @objc private func changeCompanion(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String, let character = PetCharacter(rawValue: id) else { return }
        closeQuickMenu(restoreAlert: false); _ = model.selectCharacter(character)
    }
    @objc private func replayPokeball() {
        closeQuickMenu(restoreAlert: false); closeDashboard(); petPanel.orderFrontRegardless()
        _ = petView.replaySummoning()
    }
    @objc private func testReminder() { model.testAlert() }
    @objc private func resetView() { model.resetPetView() }
    @objc private func startQuickTimer(_ item: NSMenuItem) { if let minutes = item.representedObject as? Int { model.startFocus(minutes: minutes) } }
    @objc private func showFocus() { model.dashboardTab = 2; showDashboard() }
    @objc private func toggleFocus() { model.pauseOrResumeFocus() }
    @objc private func stopFocus() { model.stopFocus() }
    @objc private func togglePet() { if petPanel.isVisible { closeDashboard(); closeQuickMenu(restoreAlert: false); bubblePanel.orderOut(nil); petPanel.orderOut(nil) } else { petPanel.orderFrontRegardless(); _ = petView.replaySummoning() } }
    @objc private func resetPosition() {
        let size = panelSize()
        let screen = NSScreen.main!.visibleFrame
        petPanel.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 35, y: screen.minY + 28))
        savePosition()
        petPanel.orderFrontRegardless()
    }
    @objc private func pauseReminders() { model.togglePause() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        petPanel.orderFrontRegardless()
        _ = petView.replaySummoning()
        return true
    }

    private func performThumbnailTest() {
        renderTimer?.invalidate()
        model.settings.soundEnabled = false
        model.settings.petSize = 230
        petView.focusTimer = nil
        var remaining = Array(PetCharacter.allCases)
        func next() {
            guard !remaining.isEmpty else { self.characterReady = nil; NSApp.terminate(nil); return }
            let character = remaining.removeFirst()
            let capture = {
                self.petView.setYaw(0)
                self.petView.preview(.idle, at: 0)
                DispatchQueue.main.asyncAfter(deadline: .now()+0.25) {
                    self.capturePreview(self.petView, name: "thumbnail-source-"+character.rawValue)
                    next()
                }
            }
            if self.petView.engine.character == character { capture() }
            else { self.characterReady = capture; _ = self.model.selectCharacter(character) }
        }
        next()
    }

    private func performRosterTest() {
        renderTimer?.invalidate()
        model.settings.soundEnabled = false
        model.settings.petSize = 230
        model.settings.tasks = [DailyTask(title: "Tarea conservada", hour: 10, minute: 0)]
        model.settings.notes = [PetNote(title: "Nota conservada", body: "Cuatro compañeros", createdAt: Date(), updatedAt: Date())]
        model.startFocus(minutes: 10); model.pauseOrResumeFocus()
        let tasks = model.settings.tasks, notes = model.settings.notes, timerID = model.settings.focusTimer?.id
        var report: [String: Any] = [:]
        var remaining: [PetCharacter] = [.pikachu, .charizard]
        func fits(_ image: NSImage) -> Bool {
            guard let data = image.tiffRepresentation, let b = NSBitmapImageRep(data: data) else { return false }
            for x in 0..<b.pixelsWide { for y in [0,1,b.pixelsHigh-2,b.pixelsHigh-1] {
                if (b.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { return false }
            } }
            for y in 0..<b.pixelsHigh { for x in [0,1,b.pixelsWide-2,b.pixelsWide-1] {
                if (b.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { return false }
            } }
            return true
        }
        func next() {
            guard !remaining.isEmpty else {
                self.characterReady = nil
                report["dataPreserved"] = self.model.settings.tasks == tasks && self.model.settings.notes == notes && self.model.settings.focusTimer?.id == timerID
                report["fourModelsBundled"] = PetCharacter.allCases.count == 4 && PetCharacter.allCases.allSatisfy { $0.isAvailable() }
                self.petView.focusTimer = nil
                self.showQuickMenu(); self.selectQuickAction(.companions)
                DispatchQueue.main.asyncAfter(deadline: .now()+0.3) {
                    if let view = self.quickMenu?.contentView { self.capturePreview(view, name: "pokedesk-quick-menu") }
                    if let view = self.quickDetail?.contentView { self.capturePreview(view, name: "pokedesk-companions") }
                    report["four3DThumbnailsBundled"] = PetCharacter.allCases.allSatisfy { Bundle.main.url(forResource: $0.thumbnailResource, withExtension: "png") != nil }
                    report["quickSelectorVisible"] = self.quickState.selected == .companions && self.quickDetail?.isVisible == true
                    report["versionVisible"] = self.menu.items.first?.title.contains(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "missing") == true
                    let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("roster-smoke-test.json")
                    try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted,.sortedKeys]).write(to: url)
                    NSApp.terminate(nil)
                }
                return
            }
            let character = remaining.removeFirst()
            self.characterReady = {
                self.petView.focusTimer = nil; self.petView.setYaw(0)
                self.petView.preview(.idle, at: 0)
                self.capturePreview(self.petView, name: character.rawValue+"-preview")
                self.petView.preview(.idle, at: 3)
                self.capturePreview(self.petView, name: character.rawValue+"-blink-preview")
                report[character.rawValue+"Blink"] = (self.petView.node(character.name+"EyesClosed")?.presentation.scale.x ?? 0) > 0.9
                report[character.rawValue+"Joints"] = self.petView.engine.jointCount == (character == .pikachu ? 49 : 87)
                var clipped = [String](), moving = [String]()
                for clip in character.clips {
                    self.petView.preview(clip, at: 0); let before = self.petView.snapshot().tiffRepresentation
                    self.petView.preview(clip, at: clip.duration*0.4)
                    if before != self.petView.snapshot().tiffRepresentation { moving.append(clip.rawValue) }
                    for angle in stride(from: 0.0, to: .pi*2, by: .pi/4) {
                        self.petView.setYaw(angle)
                        for fraction in [0.0,0.4,0.75] {
                            self.petView.preview(clip, at: clip.duration*fraction)
                            if !fits(self.petView.snapshot()) { clipped.append("\(clip.rawValue):\(angle):\(fraction)") }
                        }
                    }
                    self.petView.setYaw(0)
                }
                report[character.rawValue+"AllClipsMove"] = moving.count == 9
                report[character.rawValue+"RotationFits"] = clipped.isEmpty
                report[character.rawValue+"ClippedSamples"] = clipped
                self.captureCharacterAnimation(character == .charizard ? .happyTail : .greeting, name: character.rawValue+"-demo")
                self.characterReady = nil
                self.petView.engine.cancelSummoning()
                self.petView.summoningEnabled = true
                _ = self.applicationShouldHandleReopen(NSApp, hasVisibleWindows: true)
                report[character.rawValue+"ReopenReleases"] = self.petView.engine.summoningPhase == .release
                self.petView.engine.finishSummoningImmediately()
                report[character.rawValue+"ReplayRestores"] = self.petView.engine.summonRestored
                self.petView.summoningEnabled = false
                self.characterReady = nil
                DispatchQueue.main.asyncAfter(deadline: .now()+0.1) { next() }
            }
            _ = self.model.selectCharacter(character)
        }
        next()
    }

    private func performPokeballTest() {
        var report: [String: Any] = ["startupReleases": summonPhases == ["release"], "startupRestores": petView.engine.summonRestored]
        model.settings.petSize = 230
        model.settings.tasks = [DailyTask(title: "Tarea conservada", hour: 10, minute: 0)]
        model.settings.notes = [PetNote(title: "Nota conservada", body: "El efecto no cambia los datos", createdAt: Date(), updatedAt: Date())]
        model.settings.setCharacterYaw(0.35)
        model.startFocus(minutes: 10); model.pauseOrResumeFocus()
        let tasks = model.settings.tasks, notes = model.settings.notes, timer = model.settings.focusTimer
        pokeballReady = { [weak self] in
            guard let self else { return }
            report["switchRecallThenRelease"] = self.summonPhases == ["release", "recall", "release"]
            report["mewtwoReadyAndRestored"] = self.petView.engine.character == .mewtwo && self.petView.engine.summonRestored
            self.model.settings.setCharacterYaw(-0.7); self.model.save()
            self.pokeballReady = {
                report["returnRecallThenRelease"] = self.summonPhases.suffix(2) == ["recall", "release"]
                report["yawRestored"] = abs(self.petView.yaw-0.35) < 0.0001
                self.pokeballReady = nil
                _ = self.model.selectCharacter(.mewtwo)
                _ = self.model.selectCharacter(.arcanine)
                DispatchQueue.main.asyncAfter(deadline: .now()+0.5) {
                    report["pendingLoadCanCancel"] = self.petView.engine.character == .arcanine && self.petView.engine.loadingCharacter == nil && self.petView.engine.summonRestored
                    self.cancelRecall = true
                    _ = self.model.selectCharacter(.mewtwo)
                    DispatchQueue.main.asyncAfter(deadline: .now()+3.1) {
                        report["recallCanCancel"] = self.petView.engine.character == .arcanine && self.petView.engine.loadingCharacter == nil && self.petView.engine.summonRestored
                        self.pokeballReady = {
                            report["incomingCanCancel"] = self.petView.engine.character == .arcanine && self.petView.engine.loadingCharacter == nil && self.petView.engine.summonRestored
                            let count = self.summonPhases.count
                            self.model.settings.motionEnabled = false; self.model.save()
                            self.pokeballReady = {
                                report["reducedMotionSkipsEffects"] = self.summonPhases.count == count && self.petView.engine.summonRestored && self.petView.engine.character == .mewtwo
                                report["tasksPreserved"] = self.model.settings.tasks == tasks
                                report["notesPreserved"] = self.model.settings.notes == notes
                                report["timerPreserved"] = self.model.settings.focusTimer == timer
                                self.recordSummons = false; self.renderTimer?.invalidate()
                                self.capturePokeballTest(report)
                            }
                            _ = self.model.selectCharacter(.mewtwo)
                        }
                        self.cancelIncoming = true
                        _ = self.model.selectCharacter(.mewtwo)
                    }
                }
            }
            _ = self.model.selectCharacter(.arcanine)
        }
        _ = model.selectCharacter(.mewtwo)
    }

    private func capturePokeballTest(_ initial: [String: Any]) {
        var report = initial
        report["incomingHiddenDuringPreparation"] = hiddenIncomingChecks.count >= 4 && hiddenIncomingChecks.allSatisfy { $0 }
        petView.focusTimer = nil; petView.setYaw(0)
        let framesPerSecond = 20.0
        var incoming = [CGImage]()
        func fitsEffect() -> Bool {
            for angle in stride(from: 0.0, to: .pi*2, by: .pi/4) {
                petView.setYaw(angle)
                for phase in PetSummonPhase.allCases {
                    for time in [0.4, 0.85, 1.3, 1.7] {
                        petView.previewSummoning(phase, at: time)
                        guard let data = petView.snapshot().tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { return false }
                        for x in 0..<bitmap.pixelsWide {
                            for y in [0, bitmap.pixelsHigh-1] where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { return false }
                        }
                        for y in 0..<bitmap.pixelsHigh {
                            for x in [0, bitmap.pixelsWide-1] where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { return false }
                        }
                        if petView.containsPet(NSPoint(x: 2, y: petView.bounds.height-2)) { return false }
                    }
                }
            }
            petView.setYaw(0); petView.engine.cancelSummoning()
            return true
        }
        func frame(_ phase: PetSummonPhase, _ time: Double, white: Bool = false) -> CGImage? {
            petView.previewSummoning(phase, at: time)
            let rendered = petView.snapshot()
            let composed = NSImage(size: rendered.size)
            composed.lockFocus()
            if white { NSColor.white.setFill(); NSRect(origin: .zero, size: rendered.size).fill() }
            else { NSGradient(starting: NSColor(red: 0.09, green: 0.13, blue: 0.23, alpha: 1), ending: NSColor(red: 0.025, green: 0.04, blue: 0.085, alpha: 1))?.draw(in: NSRect(origin: .zero, size: rendered.size), angle: 90) }
            rendered.draw(in: NSRect(origin: .zero, size: rendered.size))
            composed.unlockFocus()
            guard let data = composed.tiffRepresentation else { return nil }
            let cg = NSBitmapImageRep(data: data)?.cgImage
            let peak = phase == .release ? 1.1 : 0.8
            if abs(time-peak) < 0.00001, let cg {
                let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("pokeball-\(white ? "white" : "demo")-\(phase.rawValue).png")
                if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, cg, nil); CGImageDestinationFinalize(destination)
                }
            }
            return cg
        }
        for phase in PetSummonPhase.allCases {
            if let cg = frame(phase, phase == .release ? 1.1 : 0.8, white: true) {
                let pixels = NSBitmapImageRep(cgImage: cg)
                var saturated = 0
                for y in 0..<pixels.pixelsHigh { for x in 0..<pixels.pixelsWide {
                    guard let c = pixels.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                    if phase == .release ? c.blueComponent > c.redComponent+0.3 && c.blueComponent > c.greenComponent+0.2 : c.redComponent > c.blueComponent+0.35 && c.redComponent > c.greenComponent+0.35 { saturated += 1 }
                } }
                report[phase.rawValue+"ContrastOnWhite"] = saturated > 500
                report[phase.rawValue+"SaturatedPixelsOnWhite"] = saturated
            }
        }
        for index in 0..<Int(PetSummonPhase.release.duration*framesPerSecond) {
            if let cg = frame(.release, Double(index)/framesPerSecond) { incoming.append(cg) }
        }
        petView.previewSummoning(.release, at: 0.90); capturePreview(petView, name: "pokeball-mewtwo-light")
        petView.previewSummoning(.release, at: 0.38); capturePreview(petView, name: "pokeball-3d-closed")
        petView.engine.cancelSummoning()
        report["previewCleanup"] = petView.engine.summonRestored
        report["mewtwoEffectsFitAndCornersPassThrough"] = fitsEffect()
        pokeballReady = { [weak self] in
            guard let self else { return }
            self.petView.setYaw(0); self.petView.focusTimer = nil
            report["arcanineEffectsFitAndCornersPassThrough"] = fitsEffect()
            let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("pokeball-cambio.gif")
            let count = Int(PetSummonPhase.recall.duration*framesPerSecond)+incoming.count
            if let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, count, nil) {
                CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1/framesPerSecond]] as CFDictionary
                for index in 0..<Int(PetSummonPhase.recall.duration*framesPerSecond) {
                    autoreleasepool { if let cg = frame(.recall, Double(index)/framesPerSecond) { CGImageDestinationAddImage(destination, cg, properties) } }
                }
                for cg in incoming { CGImageDestinationAddImage(destination, cg, properties) }
                report["demoCreated"] = CGImageDestinationFinalize(destination)
            }
            self.petView.previewSummoning(.recall, at: 0.85); self.capturePreview(self.petView, name: "pokeball-arcanine-recall")
            self.petView.previewSummoning(.release, at: 1.10); self.capturePreview(self.petView, name: "pokeball-arcanine-release")
            self.petView.engine.cancelSummoning()
            report["finalCleanup"] = self.petView.engine.summonRestored
            let reportURL = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("pokeball-smoke-test.json")
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: reportURL) }
            NSApp.terminate(nil)
        }
        _ = model.selectCharacter(.arcanine)
    }

    private func performCharacterTest() {
        renderTimer?.invalidate()
        model.settings.soundEnabled = false
        model.settings.petSize = 230
        model.settings.tasks = [DailyTask(title: "Tarea que conserva el cambio", hour: 10, minute: 0)]
        model.settings.notes = [PetNote(title: "Nota compartida", body: "Se conserva entre compañeros", createdAt: Date(), updatedAt: Date())]
        model.settings.petCharacter = "arcanine"
        model.settings.setCharacterYaw(0.4)
        model.startFocus(minutes: 10); model.pauseOrResumeFocus()
        let taskIDs = model.settings.tasks.map(\.id)
        let notes = model.settings.notes
        let timerID = model.settings.focusTimer?.id
        var report: [String: Any] = [:]
        characterReady = { [weak self] in
            guard let self else { return }
            report["mewtwoLoaded"] = self.petView.engine.character == .mewtwo
            report["mewtwoJoints"] = self.petView.engine.jointCount
            report["mewtwoClips"] = self.petView.engine.clipCount
            self.model.settings.setCharacterYaw(-0.7); self.model.save()
            self.characterReady = {
                report["arcanineReturns"] = self.petView.engine.character == .arcanine && self.petView.engine.clipCount == 11
                report["arcanineYawPreserved"] = abs(self.petView.yaw-0.4) < 0.0001
                self.characterReady = {
                    report["mewtwoYawPreserved"] = abs(self.petView.yaw+0.7) < 0.0001
                    report["tasksPreserved"] = self.model.settings.tasks.map(\.id) == taskIDs
                    report["notesPreserved"] = self.model.settings.notes == notes
                    report["timerPreserved"] = self.model.settings.focusTimer?.id == timerID && self.model.settings.focusTimer?.phase == .paused
                    let saved = PetModel(storageURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("arcanine-characters-smoke/estado.json"))
                    report["characterPersists"] = saved.settings.character == .mewtwo
                    report["voicePreserved"] = saved.settings.voice?.selectedEnglishVoice == self.model.settings.voice?.selectedEnglishVoice
                    self.characterReady = nil
                    DispatchQueue.main.asyncAfter(deadline: .now()+0.3) { self.captureCharacterTest(report) }
                }
                _ = self.model.selectCharacter(.mewtwo)
            }
            _ = self.model.selectCharacter(.arcanine)
        }
        if petView.engine.character == .mewtwo {
            characterReady?()
        } else { _ = model.selectCharacter(.mewtwo) }
    }

    private func captureCharacterTest(_ initial: [String: Any]) {
        var report = initial
        report["incomingHiddenDuringPreparation"] = hiddenIncomingChecks.count >= 4 && hiddenIncomingChecks.allSatisfy { $0 }
        petView.focusTimer = nil; petView.setYaw(0)
        petView.preview(.idle, at: 0)
        capturePreview(petView, name: "mewtwo-preview")
        petView.preview(.idle, at: 3)
        capturePreview(petView, name: "mewtwo-blink-preview")
        report["blinkClosesEyes"] = (petView.node("MewtwoEyesClosed")?.presentation.scale.x ?? 0) > 0.9
        report["blinkHidesPupils"] = (petView.node("MewtwoPupils")?.presentation.scale.x ?? 1) < 0.1
        var moving = [String](); var articulated = [String](); var clipped = [String]()
        func fits(_ image: NSImage) -> Bool {
            guard let data = image.tiffRepresentation, let b = NSBitmapImageRep(data: data) else { return false }
            for x in 0..<b.pixelsWide {
                for y in [0, 1, b.pixelsHigh-2, b.pixelsHigh-1] {
                    if (b.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { return false }
                }
            }
            for y in 0..<b.pixelsHigh {
                for x in [0, 1, b.pixelsWide-2, b.pixelsWide-1] {
                    if (b.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { return false }
                }
            }
            return true
        }
        for clip in PetCharacter.mewtwo.clips {
            petView.preview(clip, at: 0)
            let before = petView.snapshot().tiffRepresentation
            let joints = ["Head_052", "LArm_039", "Tail5_029", "Spine1_036"]
            let beforeJoints = joints.map { petView.node($0)?.presentation.simdOrientation.vector }
            petView.preview(clip, at: clip.duration*0.4)
            let after = petView.snapshot().tiffRepresentation
            if before != after { moving.append(clip.rawValue) }
            if beforeJoints != joints.map({ petView.node($0)?.presentation.simdOrientation.vector }) { articulated.append(clip.rawValue) }
            capturePreview(petView, name: "mewtwo-3d-\(clip.rawValue)")
            for angle in stride(from: 0.0, to: .pi*2, by: .pi/4) {
                petView.setYaw(angle)
                for fraction in [0.0, 0.4, 0.75] {
                    petView.preview(clip, at: clip.duration*fraction)
                    if !fits(petView.snapshot()) { clipped.append("\(clip.rawValue):\(angle):\(fraction)") }
                }
            }
            petView.setYaw(0)
        }
        report["allClipsMove"] = moving.count == 9
        report["allClipsArticulated"] = articulated.count == 9
        report["movingClips"] = moving
        report["rotationWithoutClipping"] = clipped.isEmpty
        report["clippedSamples"] = clipped
        petView.preview(.idle, at: 0)
        _ = petView.snapshot()
        report["petClickable"] = stride(from: 20.0, to: petView.bounds.width, by: 20).contains { x in
            stride(from: 35.0, to: petView.bounds.height, by: 20).contains { y in petView.containsPet(NSPoint(x: x, y: y)) }
        }
        model.dashboardTab = 3; showDashboard()
        DispatchQueue.main.asyncAfter(deadline: .now()+0.3) {
            if let view = self.dashboard?.contentView { self.capturePreview(view, name: "mewtwo-settings-preview") }
            self.closeDashboard(); self.toggleQuickMenu()
            if let view = self.quickMenu?.contentView { self.capturePreview(view, name: "mewtwo-quick-menu-preview") }
            report["quickMenuCharacterTheme"] = self.quickState.character == .mewtwo
            report["quickMenuVisible"] = self.quickMenu?.isVisible == true
            self.captureCharacterAnimation(.greeting, name: "mewtwo-saludo")
            let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("characters-smoke-test.json")
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url) }
            NSApp.terminate(nil)
        }
    }

    private func captureCharacterAnimation(_ clip: ArcanineClip, name: String) {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(name+".gif")
        let frames = 60
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil) else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        petView.setYaw(0)
        for frame in 0..<frames {
            autoreleasepool {
                petView.preview(clip, at: Double(frame)/Double(frames)*clip.duration)
                if let data = petView.snapshot().tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let cg = bitmap.cgImage {
                    CGImageDestinationAddImage(destination, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: clip.duration/Double(frames)]] as CFDictionary)
                }
            }
        }
        CGImageDestinationFinalize(destination)
    }

    private func performSmokeTest() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.model.settings.soundEnabled = false
            self.model.settings.petSize = 230
            self.model.calendarConnected = true
            self.model.settings.calendarFeeds = [CalendarFeed(name: "Ejemplo")]
            self.model.calendarMessage = "Agenda de ejemplo · solo para esta vista previa."
            self.model.settings.tasks = [DailyTask(title: "Preparar la reunión de equipo", hour: 10, minute: 0)]
            self.applySettings()
            self.model.meetings = [Meeting(id: "preview-meeting", title: "Reunión de equipo", start: Date().addingTimeInterval(300), end: Date().addingTimeInterval(3900), calendarName: "Trabajo · ejemplo", joinURL: URL(string: "https://meet.google.com/abc-defg-hij"), allDay: false)]
            self.model.startFocus(minutes: 5)
            self.model.pauseOrResumeFocus()
            self.model.testAlert()
            let head = self.petView.node("Head_054")?.presentation.simdOrientation.vector
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.writeSmokeReport(nativePlaybackAdvances: head != self.petView.node("Head_054")?.presentation.simdOrientation.vector)
            }
        }
    }

    private func writeSmokeReport(nativePlaybackAdvances: Bool) {
            var report: [String: Any] = [
                "viewWidth": petView.bounds.width,
                "viewHeight": petView.bounds.height,
                "nativePlaybackAdvances": nativePlaybackAdvances,
                "petVisible": self.petPanel.isVisible,
                "borderless": !self.petPanel.styleMask.contains(.titled) && !self.petPanel.styleMask.contains(.resizable),
                "opaque": self.petPanel.isOpaque,
                "backgroundAlpha": self.petPanel.backgroundColor.alphaComponent,
                "windowShadow": self.petPanel.hasShadow,
                "floatingLevel": self.petPanel.level.rawValue,
                "allSpaces": self.petPanel.collectionBehavior.contains(.canJoinAllSpaces),
                "fullscreenAuxiliary": self.petPanel.collectionBehavior.contains(.fullScreenAuxiliary),
                "noPermanentDashboard": self.dashboard == nil,
                "cornerPassesClicks": !self.petView.containsPet(NSPoint(x: 1, y: 1)),
                "centerIsClickable": self.petView.containsPet(NSPoint(x: self.petView.bounds.midX, y: self.petView.bounds.midY)),
                "menuAvailable": self.statusItem.menu != nil,
                "pngLoaded": self.petView.image.size.width > 0,
                "reminderVisible": self.bubblePanel.isVisible,
                "reminderHasContent": self.model.currentAlert != nil,
                "reminderTransparentPanel": !self.bubblePanel.isOpaque && self.bubblePanel.backgroundColor.alphaComponent == 0
                ,"faceTimer": self.petView.focusTimer?.display(at: Date()) ?? ""
                ,"faceTimerPaused": self.petView.focusTimer?.phase == .paused
                ,"oldSettingsCompatible": self.model.settings.calendarFeeds != nil
                ,"meetingAlertHasJoinURL": self.model.currentAlert?.joinURL?.host == "meet.google.com"
                ,"character": "Arcanine"
                ,"appDisplayName": Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? ""
                ,"appExecutable": Bundle.main.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ?? ""
                ,"separateDataIdentity": Bundle.main.bundleIdentifier == "io.github.franciscorrandom.arcanine.ical"
                ,"statusMenuRenamed": self.menu.items.contains { $0.title == "Salir de PokéDesk" } && !self.menu.items.contains { $0.title.contains("Miga") }
                ,"menuTheme": "Pokédex · rojo, crema y Fuego"
                ,"model3DLoaded": self.petView.engine.ready
                ,"jointCount": self.petView.engine.jointCount
                ,"animationClipCount": self.petView.engine.clipCount
                ,"alertAnimation": self.petView.currentClip == .alert
                ,"englishVoiceChoices": EnglishVoice.allCases.map(\.name)
                ,"recordedClipsReady": EnglishVoice.allCases.reduce(0) { $0 + VoiceClip.allCases.count - self.model.voiceSpeaker.missingClips(voice: $1).count }
                ,"recordedClipsPending": EnglishVoice.allCases.reduce(0) { $0 + self.model.voiceSpeaker.missingClips(voice: $1).count }
                ,"meetingAudioReadyBothVoices": EnglishVoice.allCases.allSatisfy { voice in
                    self.model.voiceSpeaker.audioURL(.meeting, voice: voice) != nil && self.model.voiceSpeaker.audioURL(.meetingWithLink, voice: voice) != nil
                }
            ]
            self.petView.display()
            self.capturePreview(self.petView, name: "focus-preview")
            if let view = self.bubblePanel.contentView { self.capturePreview(view, name: "meeting-preview") }
            report.merge(self.testNotes()) { _, new in new }
            self.testQuickMenu { quickChecks in
            report.merge(quickChecks) { _, new in new }
            self.showHome()
            report["floatingMenuBorderless"] = self.dashboard?.styleMask.contains(.titled) == false
            report["floatingMenuTransparent"] = self.dashboard?.isOpaque == false
            report["floatingMenuVisible"] = self.dashboard?.isVisible == true
            report["floatingMenuOnScreen"] = self.dashboard.map { ($0.screen?.visibleFrame ?? .zero).contains($0.frame) } ?? false
            report["floatingMenuAllSpaces"] = self.dashboard?.collectionBehavior.contains(.canJoinAllSpaces) == true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let view = self.dashboard?.contentView { self.capturePreview(view, name: "menu-preview") }
                self.captureDashboardPreviews([(0, "pokedex-agenda-preview"), (1, "pokedex-tasks-preview"), (2, "hud-focus-preview"), (3, "hud-voice-settings-preview"), (4, "pokedex-animations-preview"), (5, "pokedex-notes-preview")]) {
                    for voice in EnglishVoice.allCases {
                        self.model.selectEnglishVoice(voice.rawValue)
                        let preview = NSHostingView(rootView: DashboardView(model: self.model).voicePreferences
                            .padding(20).foregroundStyle(ArcanineTheme.ink).background(ArcanineTheme.paper)
                            .tint(ArcanineTheme.red).toggleStyle(.switch).buttonStyle(PokedexButtonStyle()).preferredColorScheme(.light))
                        preview.frame = NSRect(x: 0, y: 0, width: 430, height: 560)
                        preview.appearance = NSAppearance(named: .aqua)
                        self.capturePreview(preview, name: "\(voice.rawValue)-voice-settings-preview")
                    }
                    let savedVoice = PetModel(storageURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("arcanine-ical-smoke/estado.json"))
                    report["englishVoiceSelectionPersists"] = savedVoice.settings.voice?.selectedEnglishVoice == .holden
                    self.closeDashboard()
                    report["floatingMenuCloses"] = self.dashboard?.isVisible == false
                    self.model.currentAlert = nil
                    self.model.settings.focusTimer?.phase = .running
                    self.model.settings.focusTimer?.deadline = Date().addingTimeInterval(-1)
                    self.model.checkFocusTimer()
                    let completionID = self.model.currentAlert?.id
                    self.model.checkFocusTimer()
                    self.renderTick()
                    report["timerFinishesOnce"] = self.model.settings.focusTimer?.notified == true && self.model.currentAlert?.focusTimerID == self.model.settings.focusTimer?.id && completionID == self.model.currentAlert?.id
                    report["faceRestoredAfterTimer"] = self.petView.focusTimer == nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    report["completionAnimation"] = self.petView.currentClip == .celebration
                    self.petView.preview(.idle, at: 0)
                    self.capturePreview(self.petView, name: "arcanine-preview")
                    self.petView.preview(.idle, at: 3)
                    self.capturePreview(self.petView, name: "arcanine-blink-preview")
                    report["blinkClosesEyes"] = (self.petView.node("ArcanineEyesClosed")?.presentation.scale.x ?? 0) > 0.9
                    report["blinkHidesOpenEyes"] = (self.petView.node("ArcanineEyesOpen")?.presentation.scale.x ?? 1) < 0.1
                    var movingClips: [String] = []
                    var hitSamples: [String: [[String: Any]]] = [:]
                    for clip in ArcanineClip.allCases {
                        self.petView.preview(clip, at: 0)
                        let before = self.petView.snapshot().tiffRepresentation
                        self.petView.preview(clip, at: clip.duration * 0.4)
                        let after = self.petView.snapshot().tiffRepresentation
                        if before != after { movingClips.append(clip.rawValue) }
                        self.capturePreview(self.petView, name: "arcanine-3d-\(clip.rawValue)")
                        var samples: [[String: Any]] = []
                        for x in stride(from: 10.0, to: self.petView.bounds.width, by: 15) {
                            for y in stride(from: 35.0, to: self.petView.bounds.height, by: 15) {
                                samples.append(["x": x, "y": y, "hit": self.petView.containsPet(NSPoint(x: x, y: y))])
                            }
                        }
                        hitSamples[clip.rawValue] = samples
                    }
                    report["hitSamples"] = hitSamples
                    report["movingClips"] = movingClips
                    report["allClipsMove"] = movingClips.count == ArcanineClip.allCases.count
                    report.merge(self.testPetInteractions()) { _, new in new }
                    report.merge(self.testRotation()) { _, new in new }
                    self.capturePetAnimation()
                    let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("smoke-test.json")
                    if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: url) }
                    NSApp.terminate(nil)
                    }
                }
            }
            }
    }

    private func testQuickMenu(completion: @escaping ([String: Any]) -> Void) {
        var checks: [String: Any] = [:]
        _ = petView.accessibilityPerformPress()
        checks["petClickOpensQuickMenu"] = quickMenu?.isVisible == true && dashboard?.isVisible != true
        checks["quickMenuTransparent"] = quickMenu?.isOpaque == false && quickMenu?.backgroundColor.alphaComponent == 0
        checks["quickMenuBorderless"] = quickMenu?.styleMask.contains(.titled) == false
        checks["quickMenuAllSpaces"] = quickMenu?.collectionBehavior.contains(.canJoinAllSpaces) == true
        checks["quickMenuAbovePet"] = quickMenu!.frame.midY > petPanel.frame.midY
        checks["quickMenuOnScreen"] = petPanel.screen!.visibleFrame.contains(quickMenu!.frame)
        checks["quickMenuActions"] = PetQuickAction.allCases.map(\.title)
        quickHostingView?.layoutSubtreeIfNeeded()
        let host = quickHostingView!
        checks["quickMenuEmptyCenterPassesClicks"] = !host.containsControl(NSPoint(x: QuickMenuLayout.width / 2, y: host.isFlipped ? 94 : 96))
        checks["quickMenuButtonsClickable"] = (0..<PetQuickAction.allCases.count).allSatisfy { index in
            let p = QuickMenuLayout.buttonCenter(index)
            return host.containsControl(NSPoint(x: p.x, y: host.isFlipped ? p.y : QuickMenuLayout.height - p.y))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            checks["quickMenuNativeHitTests"] = (0..<PetQuickAction.allCases.count).allSatisfy { index in
                let point = QuickMenuLayout.buttonCenter(index)
                let local = NSPoint(x: point.x, y: host.isFlipped ? point.y : QuickMenuLayout.height - point.y)
                return host.hitTest(host.convert(local, to: host.superview)) != nil
            }
            self.capturePreview(host, name: "accesos-semicirculares-preview")
            self.captureQuickContext()
            self.captureQuickDetails([.agenda, .focus, .notes, .animations]) {
                checks["quickDetailsStayCompact"] = self.dashboard?.isVisible != true && self.quickDetail!.frame.width == 350
                checks["quickDetailOnScreen"] = self.petPanel.screen!.visibleFrame.contains(self.quickDetail!.frame)
                self.selectQuickAction(.animations)
                checks["quickSelectionTogglesClosed"] = self.quickDetail?.isVisible != true && self.quickMenu?.isVisible == true
                self.selectQuickAction(.petting)
                checks["quickPettingWorks"] = self.petView.currentClip == .petting && self.quickMenu?.isVisible != true && self.dashboard?.isVisible != true
                let timer = self.model.settings.focusTimer
                var timerChecks = true
                for minutes in [5, 10, 30] {
                    self.showQuickMenu(); self.selectQuickAction(.focus); self.runQuickTimer(minutes)
                    timerChecks = timerChecks && self.model.settings.focusTimer?.durationSeconds == minutes * 60 && self.quickMenu?.isVisible != true && self.dashboard?.isVisible != true
                }
                checks["quickTimersStartWithoutDashboard"] = timerChecks
                self.model.settings.focusTimer = timer; self.model.errorMessage = nil; self.model.save()
                self.showQuickMenu(); self.selectQuickAction(.animations); self.runQuickAnimation(.sit)
                checks["quickAnimationWorks"] = self.petView.currentClip == .sit && self.quickDetail?.isVisible != true
                self.showQuickMenu(); self.selectQuickAction(.openPanel)
                checks["quickOpenShowsFullPanel"] = self.dashboard?.isVisible == true && self.model.dashboardTab == -1 && self.quickMenu?.isVisible != true
                self.closeDashboard(); self.showQuickMenu()
                _ = self.petView.accessibilityPerformPress()
                checks["secondPetClickClosesQuickMenu"] = self.quickMenu?.isVisible != true
                self.showQuickMenu(); self.quickMenu?.cancelOperation(nil)
                checks["escapeClosesQuickMenu"] = self.quickMenu?.isVisible != true
                self.petView.play(.alert, manual: true)
                completion(checks)
            }
        }
    }

    private func testNotes() -> [String: Any] {
        // Sample notes are written only to the isolated --smoke-test store.
        model.settings.notes = []
        let now = Date()
        model.noteDraft = NoteDraft(title: "Ideas para la reunión", body: "Revisar prioridades y próximos pasos del equipo.", category: "Trabajo")
        let created = model.saveNote(now: now.addingTimeInterval(-3600))
        let first = model.noteDraft.id
        model.noteDraft.body += "\nPreparar un resumen después de la reunión."
        let edited = model.saveNote(now: now)
        let versions = model.editingNote?.revisions.count == 1
        model.newNote()
        model.noteDraft = NoteDraft(title: "Una idea para después", body: "Reservar un rato para leer y dar un paseo.")
        let uncategorized = model.saveNote(now: now.addingTimeInterval(-1800))
        let second = model.noteDraft.id!
        let archived = model.setNoteArchived(second, archived: true) && NoteRules.filtered(model.notes).count == 1
        let recovered = model.setNoteArchived(second, archived: false) && NoteRules.filtered(model.notes).count == 2
        let restored = PetModel(storageURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("arcanine-ical-smoke/estado.json"))
        let persisted = restored.notes == model.notes
        model.newNote()
        return ["notesCreatedEdited": created && edited && uncategorized && first != nil,
                "notesVersionsRetained": versions, "notesArchiveRestore": archived && recovered,
                "notesPersist": persisted, "notesSearchAndCategory": NoteRules.filtered(model.notes, query: "reunion", category: "trabajo").count == 1,
                "quickNotesAvailable": PetQuickAction.notes.tab == 5 && PetQuickAction.allCases.count == QuickMenuLayout.buttonCount]
    }

    private func captureQuickDetails(_ actions: [PetQuickAction], completion: @escaping () -> Void) {
        guard let action = actions.first else { completion(); return }
        selectQuickAction(action)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let view = self.quickDetail?.contentView { self.capturePreview(view, name: "quick-\(action.rawValue)-preview") }
            self.captureQuickDetails(Array(actions.dropFirst()), completion: completion)
        }
    }

    private func captureQuickContext() {
        guard let quickMenu, let host = quickMenu.contentView,
              let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let bounds = petPanel.frame.union(quickMenu.frame)
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        NSColor(ArcanineTheme.paper).setFill()
        NSRect(origin: .zero, size: bounds.size).fill()
        petView.snapshot().draw(in: NSRect(x: petPanel.frame.minX - bounds.minX, y: petPanel.frame.minY - bounds.minY, width: petPanel.frame.width, height: petPanel.frame.height))
        if let cg = bitmap.cgImage { NSImage(cgImage: cg, size: host.bounds.size).draw(in: NSRect(x: quickMenu.frame.minX - bounds.minX, y: quickMenu.frame.minY - bounds.minY, width: quickMenu.frame.width, height: quickMenu.frame.height)) }
        image.unlockFocus()
        if let data = image.tiffRepresentation, let out = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
            try? out.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("arcanine-accesos-contexto.png"))
        }
    }

    private func testPetInteractions() -> [String: Any] {
        var checks: [String: Any] = [:]
        let origin = petPanel.frame.origin, yaw = petView.yaw
        let point = NSPoint(x: petView.bounds.midX, y: petView.bounds.midY)
        func event(_ type: NSEvent.EventType, _ x: Double, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: point.x + x, y: point.y), modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: petPanel.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        petView.mouseDown(with: event(.leftMouseDown, 0, .shift))
        petView.mouseDragged(with: event(.leftMouseDragged, 15, .shift))
        let revision = petView.animationRevision
        checks["shiftDragPets"] = petView.currentClip == .petting
        petView.mouseDragged(with: event(.leftMouseDragged, -20, []))
        petView.mouseDragged(with: event(.leftMouseDragged, 25, []))
        petView.mouseUp(with: event(.leftMouseUp, 25, []))
        checks["pettingDoesNotRestartEveryMouseEvent"] = petView.animationRevision == revision
        checks["pettingDoesNotMoveOrRotate"] = petPanel.frame.origin == origin && petView.yaw == yaw
        checks["pettingDoesNotOpenMenu"] = dashboard?.isVisible != true
        checks["pettingHintAvailable"] = petView.toolTip?.contains("Mayús") == true
        var requested: [String] = []
        for clip in ArcanineClip.allCases {
            model.requestAnimation(clip)
            if petView.currentClip == clip { requested.append(clip.rawValue) }
        }
        checks["manualAnimationChoices"] = requested
        checks["allAnimationsCanBeRequested"] = requested.count == ArcanineClip.allCases.count
        model.settings.motionEnabled = false
        let before = petView.animationRevision
        model.requestAnimation(.sit)
        checks["manualAnimationsRespectDisabledMotion"] = petView.animationRevision == before && model.errorMessage != nil
        model.settings.motionEnabled = true; model.errorMessage = nil
        petView.setYaw(0)
        func positions(_ clip: ArcanineClip, _ time: Double) -> [String: SIMD3<Float>] {
            petView.preview(clip, at: time)
            _ = petView.snapshot()
            let names = ["Waist_03", "LHand_049", "RHand_078", "LFoot_08", "RFoot_019"]
            return Dictionary(uniqueKeysWithValues: names.map { ($0, petView.node($0)!.presentation.simdWorldPosition) })
        }
        let standing = positions(.idle, 0)
        var error: Float = 0
        for time in stride(from: 0.0, through: ArcanineClip.sit.duration, by: 0.2) {
            let posed = positions(.sit, time)
            for name in ["LHand_049", "RHand_078"] {
                error = max(error, simd_distance(posed[name]!, standing[name]!))
            }
        }
        let seated = positions(.sit, 3.2)
        checks["sitLowersHips"] = standing["Waist_03"]!.y - seated["Waist_03"]!.y > 0.4
        checks["sitTucksBackPaws"] = seated["LFoot_08"]!.z - standing["LFoot_08"]!.z > 0.35
        checks["sitFrontPawError"] = error
        checks["sitKeepsFrontPawsPlanted"] = error < 0.003
        let finished = positions(.sit, ArcanineClip.sit.duration)
        checks["sitReturnsToStanding"] = simd_distance(finished["Waist_03"]!, standing["Waist_03"]!) < 0.001
        petView.setYaw(.pi / 2)
        petView.preview(.sit, at: 3.2)
        capturePreview(petView, name: "arcanine-sentado-perfil")
        petView.setYaw(0)
        _ = positions(.petting, 2)
        checks["pettingRelaxesEyes"] = petView.node("ArcanineEyesClosed")!.presentation.scale.x > 0.9
        petView.preview(.petting, at: 2)
        capturePreview(petView, name: "arcanine-caricias-preview")
        petView.setYaw(yaw)
        return checks
    }

    private func testRotation() -> [String: Any] {
        var checks: [String: Any] = [:]
        let originalOrigin = petPanel.frame.origin
        let point = NSPoint(x: petView.bounds.midX, y: petView.bounds.midY)
        func event(_ type: NSEvent.EventType, _ location: NSPoint, _ flags: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: petPanel.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        model.resetPetView()
        petView.preview(.idle, at: 0)
        petView.mouseDown(with: event(.leftMouseDown, point, .option))
        petView.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: point.x + 112.5, y: point.y + 80), []))
        petView.mouseUp(with: event(.leftMouseUp, NSPoint(x: point.x + 112.5, y: point.y + 80), []))
        _ = petView.snapshot()
        checks["optionDragRotates"] = abs(petView.yaw - .pi / 2) < 0.00001
        checks["rotationDoesNotMovePanel"] = petPanel.frame.origin == originalOrigin
        checks["rotationDoesNotOpenMenu"] = dashboard?.isVisible != true
        checks["rotationHasNoPitchOrRoll"] = petView.engine.orientationAngles.x == 0 && petView.engine.orientationAngles.z == 0
        let restored = PetModel(storageURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("arcanine-ical-smoke/estado.json"))
        checks["rotationPersists"] = restored.settings.petYaw == petView.yaw
        let angle = petView.yaw
        petView.mouseDown(with: event(.leftMouseDown, point, .option))
        petView.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: point.x, y: point.y + 80), .option))
        petView.mouseUp(with: event(.leftMouseUp, NSPoint(x: point.x, y: point.y + 80), .option))
        checks["verticalRotationDragIgnored"] = petView.yaw == angle && petPanel.frame.origin == originalOrigin && dashboard?.isVisible != true
        petView.mouseDown(with: event(.leftMouseDown, point, []))
        petView.mouseDragged(with: event(.leftMouseDragged, NSPoint(x: point.x - 24, y: point.y + 15), .option))
        petView.mouseUp(with: event(.leftMouseUp, point, .option))
        checks["normalDragStillMoves"] = abs(petPanel.frame.minX - (originalOrigin.x - 24)) < 0.001 && abs(petPanel.frame.minY - (originalOrigin.y + 15)) < 0.001
        checks["normalDragDoesNotRotate"] = petView.yaw == angle
        petPanel.setFrameOrigin(originalOrigin)
        savePosition()
        var profiles: [String: [[String: Any]]] = [:]
        for (name, yaw) in [("original", 0.0), ("perfil", Double.pi / 2), ("espalda", Double.pi), ("otro-perfil", -Double.pi / 2)] {
            petView.setYaw(yaw)
            petView.preview(.idle, at: 0)
            capturePreview(petView, name: "arcanine-vista-\(name)")
            var samples: [[String: Any]] = []
            for x in stride(from: 10.0, to: petView.bounds.width, by: 15) {
                for y in stride(from: 35.0, to: petView.bounds.height, by: 15) {
                    samples.append(["x": x, "y": y, "hit": petView.containsPet(NSPoint(x: x, y: y))])
                }
            }
            profiles[name] = samples
        }
        checks["rotationHitSamples"] = profiles
        func fits(_ image: NSImage) -> Bool {
            guard let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data) else { return false }
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 2) {
                if bitmap.colorAt(x: x, y: 0)!.alphaComponent > 0 || bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 1)!.alphaComponent > 0 { return false }
            }
            for y in stride(from: 0, to: bitmap.pixelsHigh, by: 2) {
                if bitmap.colorAt(x: 0, y: y)!.alphaComponent > 0 || bitmap.colorAt(x: bitmap.pixelsWide - 1, y: y)!.alphaComponent > 0 { return false }
            }
            return true
        }
        var fullCircleFits = true
        var croppedAngles: [Int] = []
        for degrees in stride(from: 0, to: 360, by: 15) {
            petView.setYaw(Double(degrees) * .pi / 180)
            petView.preview(.idle, at: 0)
            let complete = autoreleasepool { fits(petView.snapshot()) }
            if !complete {
                fullCircleFits = false; croppedAngles.append(degrees)
                if croppedAngles.count == 1 { capturePreview(petView, name: "perfil-recortado") }
            }
        }
        var animationsFitAfterRotation = true
        var croppedClips: [String] = []
        for degrees in stride(from: 0, to: 360, by: 45) {
            petView.setYaw(Double(degrees) * .pi / 180)
            for clip in ArcanineClip.allCases {
                for progress in [0.25, 0.5, 0.75] {
                    petView.preview(clip, at: clip.duration * progress)
                    let complete = autoreleasepool { fits(petView.snapshot()) }
                    if !complete {
                        animationsFitAfterRotation = false
                        croppedClips.append("\(degrees)° \(clip.rawValue) \(progress)")
                        if croppedClips.count == 1 { capturePreview(petView, name: "animacion-recortada") }
                    }
                }
            }
        }
        checks["fullCircleFits"] = fullCircleFits
        checks["animationsFitAfterRotation"] = animationsFitAfterRotation
        checks["croppedAngles"] = croppedAngles
        checks["croppedClips"] = croppedClips
        petView.setYaw(angle)
        resetView()
        let savedReset = PetModel(storageURL: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("arcanine-ical-smoke/estado.json"))
        checks["resetViewWorks"] = petView.yaw == 0 && savedReset.settings.petYaw == nil && petPanel.frame.origin == originalOrigin
        checks["rotationHintAvailable"] = petView.toolTip?.contains("Option") == true
        checks["resetViewMenuAvailable"] = menu.items.contains { $0.title == "Restablecer vista" }
        return checks
    }

    private func captureDashboardPreviews(_ tabs: [(Int, String)], completion: @escaping () -> Void) {
        guard let next = tabs.first else { completion(); return }
        model.dashboardTab = next.0
        positionDashboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let view = self.dashboard?.contentView { self.capturePreview(view, name: next.1) }
            self.captureDashboardPreviews(Array(tabs.dropFirst()), completion: completion)
        }
    }

    private func capturePetAnimation() {
        let url = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("arcanine-animacion.gif")
        let frames = 100
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, frames, nil) else { return }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<frames {
            autoreleasepool {
                petView.preview(.chaseTail, at: Double(frame) / 25)
                let image = petView.snapshot()
                if let data = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let cg = bitmap.cgImage {
                    CGImageDestinationAddImage(destination, cg, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 25]] as CFDictionary)
                }
            }
        }
        CGImageDestinationFinalize(destination)
    }

    private func capturePreview(_ view: NSView, name: String) {
        view.layoutSubtreeIfNeeded()
        view.display()
        if let pet = view as? PetView {
            if let data = pet.snapshot().tiffRepresentation, let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(name + ".png"))
            }
            return
        }
        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try? data.write(to: Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(name + ".png"))
            }
        }
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.run()
}

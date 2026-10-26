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
            DispatchQueue.main.async {
                // Desktop clicks from the operator must not interrupt isolated UI captures.
                guard let self, !self.smokeTest else { return }
                self.closeDashboard(); self.closeQuickMenu()
            }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, !self.smokeTest, event.window != self.dashboard, event.window != self.quickMenu,
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
        petView.ambientRotationEnabled = !smokeTest && (model.settings.ambientRotationEnabled ?? true)
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
        petView.menuOpen = dashboard?.isVisible == true || quickMenu?.isVisible == true || quickDetail?.isVisible == true
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
        positionFloatingPanel(dashboard, width: 500, height: model.dashboardTab == 5 ? 760 : 710)
    }

    private func positionQuickMenu() {
        guard let quickMenu else { return }
        let screen = petPanel.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let bounds = FloatingRect(x: screen.minX, y: screen.minY, width: screen.width, height: screen.height)
        let rect = QuickMenuLayout.place(anchorX: petPanel.frame.midX,
            anchorY: petPanel.frame.minY + 28 + (petPanel.frame.height - 28) * 0.82, screen: bounds)
        quickMenu.setFrame(NSRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height), display: true)
        quickState.origin = CGPoint(x: petPanel.frame.midX - rect.x,
            y: rect.maxY - (petPanel.frame.minY + 28 + (petPanel.frame.height - 28) * 0.5))
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
        quickState.presentation += 1
        quickState.expanded = false
        quickState.interactionReady = false
        quickDetail?.orderOut(nil)
        positionQuickMenu()
        bubblePanel.orderOut(nil)
        quickMenu?.ignoresMouseEvents = false
        quickMenu?.makeKeyAndOrderFront(nil)
        let presentation = quickState.presentation
        DispatchQueue.main.async { [weak self] in
            guard let self, self.quickState.presentation == presentation, self.quickMenu?.isVisible == true else { return }
            self.quickState.expanded = true
            let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.quickState.presentation == presentation, self.quickMenu?.isVisible == true else { return }
                self.quickState.interactionReady = true
            }
        }
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
        quickState.presentation += 1
        quickState.expanded = false
        quickState.interactionReady = false
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
                    if character == .pikachu || character == .lucario {
                        let front = atan2(3.2,5.4)
                        let profiles: [(String,Double)] = character == .lucario
                            ? [("frente",front),("perfil",front+Double.pi/2),("espalda",front+Double.pi),("tres-cuartos",front+Double.pi*1.25)]
                            : [("frente",front),("perfil",front+Double.pi/2)]
                        for (name, angle) in profiles {
                            self.petView.setYaw(angle)
                            self.petView.preview(.idle, at: 0)
                            self.capturePreview(self.petView, name: character.rawValue+"-postura-"+name)
                        }
                        self.petView.setYaw(0)
                    }
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
        model.settings.notes = [PetNote(title: "Nota conservada", body: "Seis compañeros", createdAt: Date(), updatedAt: Date())]
        model.startFocus(minutes: 10); model.pauseOrResumeFocus()
        let tasks = model.settings.tasks, notes = model.settings.notes, timerID = model.settings.focusTimer?.id
        var report: [String: Any] = [:]
        var remaining = Array(PetCharacter.allCases.dropFirst())
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
                report["sixModelsBundled"] = PetCharacter.allCases.count == 6 && PetCharacter.allCases.allSatisfy { $0.isAvailable() }
                self.petView.focusTimer = nil
                self.showQuickMenu(); self.selectQuickAction(.companions)
                DispatchQueue.main.asyncAfter(deadline: .now()+0.3) {
                    if let view = self.quickMenu?.contentView { self.capturePreview(view, name: "pokedesk-quick-menu") }
                    if let view = self.quickDetail?.contentView { self.capturePreview(view, name: "pokedesk-companions") }
                    report["six3DThumbnailsBundled"] = PetCharacter.allCases.allSatisfy { Bundle.main.url(forResource: $0.thumbnailResource, withExtension: "png") != nil }
                    report["quickSelectorVisible"] = self.quickState.selected == .companions && self.quickDetail?.isVisible == true
                    report["quickSelectorSelection"] = self.quickState.selected?.rawValue ?? "none"
                    report["quickSelectorPanelVisible"] = self.quickDetail?.isVisible == true
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
                report[character.rawValue+"Joints"] = self.petView.engine.jointCount == character.expectedJoints
                var clipped = [String](), moving = [String]()
                for clip in character.clips {
                    self.petView.preview(clip, at: 0); let before = self.petView.snapshot().tiffRepresentation
                    self.petView.preview(clip, at: clip.duration*0.4)
                    if before != self.petView.snapshot().tiffRepresentation { moving.append(clip.rawValue) }
                    if character == .lucario || character == .gengar {
                        self.capturePreview(self.petView, name: character.rawValue+"-3d-"+clip.rawValue)
                    }
                    for angle in stride(from: 0.0, to: .pi*2, by: .pi/4) {
                        self.petView.setYaw(angle)
                        for fraction in [0.0,0.4,0.75] {
                            self.petView.preview(clip, at: clip.duration*fraction)
                            if !fits(self.petView.snapshot()) { clipped.append("\(clip.rawValue):\(angle):\(fraction)") }
                        }
                    }
                    self.petView.setYaw(0)
                }
                report[character.rawValue+"AllClipsMove"] = moving.count == character.clips.count
                report[character.rawValue+"RotationFits"] = clipped.isEmpty
                report[character.rawValue+"ClippedSamples"] = clipped
                self.captureCharacterAnimation(character == .charizard || character == .gengar ? .happyTail : .greeting, name: character.rawValue+"-demo")
                if character == .lucario { self.captureCharacterAnimation(.idle, name: "lucario-reposo") }
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
                    if !…39383 tokens truncated…: "3.1.1",
      "resolved": "https://registry.npmjs.org/path-key/-/path-key-3.1.1.tgz",
      "integrity": "sha512-ojmeN0qd+y0jszEtoY48r0Peq5dwMEkIlCOu6Q5f41lfkswXuKtYrhgoTpLnyIcHm24Uhqx+5Tqm2InSwLhE6Q==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/pe-library": {
      "version": "0.4.1",
      "resolved": "https://registry.npmjs.org/pe-library/-/pe-library-0.4.1.tgz",
      "integrity": "sha512-eRWB5LBz7PpDu4PUlwT0PhnQfTQJlDDdPa35urV4Osrm0t0AqQFGn+UIkU3klZvwJ8KPO3VbBFsXquA6p6kqZw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=12",
        "npm": ">=6"
      },
      "funding": {
        "type": "github",
        "url": "https://github.com/sponsors/jet2jet"
      }
    },
    "node_modules/picocolors": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/picocolors/-/picocolors-1.1.1.tgz",
      "integrity": "sha512-xceH2snhtb5M9liqDsmEw56le376mTZkEX/jEb/RxNFyegNul7eNslCXP9FDj/Lcu0X8KEyMceP2ntpaHrDEVA==",
      "dev": true,
      "license": "ISC"
    },
    "node_modules/picomatch": {
      "version": "4.0.7",
      "resolved": "https://registry.npmjs.org/picomatch/-/picomatch-4.0.7.tgz",
      "integrity": "sha512-qcJu88Q2IWqJsDD529JKMdwGm/dvInW4HvQnRwiH9JtihJvzGOscDtHE3x1pBKeUOTysQ8kVmLnJ2kJu7yhcGA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=12"
      },
      "funding": {
        "url": "https://github.com/sponsors/jonschlinkert"
      }
    },
    "node_modules/pkijs": {
      "version": "3.4.1",
      "resolved": "https://registry.npmjs.org/pkijs/-/pkijs-3.4.1.tgz",
      "integrity": "sha512-Oo/NZcSWccq8KyoG7gLE9fnltgHns+pNCjCAp/WmjsUySi+sX7y4z4Xqu4fVb42CDHzRPl33fjzT15V1wvcyhA==",
      "dev": true,
      "license": "BSD-3-Clause",
      "workspaces": [
        "website"
      ],
      "dependencies": {
        "@noble/hashes": "1.8.0",
        "asn1js": "^3.0.6",
        "bytestreamjs": "^2.0.1",
        "pvtsutils": "^1.3.6",
        "pvutils": "^1.1.3",
        "tslib": "^2.8.1"
      },
      "engines": {
        "node": ">=16.0.0"
      }
    },
    "node_modules/pkijs/node_modules/@noble/hashes": {
      "version": "1.8.0",
      "resolved": "https://registry.npmjs.org/@noble/hashes/-/hashes-1.8.0.tgz",
      "integrity": "sha512-jCs9ldd7NwzpgXDIf6P3+NrHh9/sD6CQdxHyjQI+h/6rDNo88ypBxxz45UDuZHz9r3tNz7N/VInSVoVdtXEI4A==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": "^14.21.3 || >=16"
      },
      "funding": {
        "url": "https://paulmillr.com/funding/"
      }
    },
    "node_modules/plist": {
      "version": "3.1.0",
      "resolved": "https://registry.npmjs.org/plist/-/plist-3.1.0.tgz",
      "integrity": "sha512-uysumyrvkUX0rX/dEVqt8gC3sTBzd4zoWfLeS29nb53imdaXVvLINYXTI2GNqzaMuvacNx4uJQ8+b3zXR0pkgQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@xmldom/xmldom": "^0.8.8",
        "base64-js": "^1.5.1",
        "xmlbuilder": "^15.1.1"
      },
      "engines": {
        "node": ">=10.4.0"
      }
    },
    "node_modules/postject": {
      "version": "1.0.0-alpha.6",
      "resolved": "https://registry.npmjs.org/postject/-/postject-1.0.0-alpha.6.tgz",
      "integrity": "sha512-b9Eb8h2eVqNE8edvKdwqkrY6O7kAwmI8kcnBv1NScolYJbo59XUF0noFq+lxbC1yN20bmC0WBEbDC5H/7ASb0A==",
      "dev": true,
      "license": "MIT",
      "optional": true,
      "peer": true,
      "dependencies": {
        "commander": "^9.4.0"
      },
      "bin": {
        "postject": "dist/cli.js"
      },
      "engines": {
        "node": ">=14.0.0"
      }
    },
    "node_modules/postject/node_modules/commander": {
      "version": "9.5.0",
      "resolved": "https://registry.npmjs.org/commander/-/commander-9.5.0.tgz",
      "integrity": "sha512-KRs7WVDKg86PWiuAqhDrAQnTXZKraVcCc6vFdL14qrZ/DcWwuRo7VoiYXalXO7S5GKpqYiVEwCbgFDfxNHKJBQ==",
      "dev": true,
      "license": "MIT",
      "optional": true,
      "peer": true,
      "engines": {
        "node": "^12.20.0 || >=14"
      }
    },
    "node_modules/proc-log": {
      "version": "6.1.0",
      "resolved": "https://registry.npmjs.org/proc-log/-/proc-log-6.1.0.tgz",
      "integrity": "sha512-iG+GYldRf2BQ0UDUAd6JQ/RwzaQy6mXmsk/IzlYyal4A4SNFw54MeH4/tLkF4I5WoWG9SQwuqWzS99jaFQHBuQ==",
      "dev": true,
      "license": "ISC",
      "engines": {
        "node": "^20.17.0 || >=22.9.0"
      }
    },
    "node_modules/process-nextick-args": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/process-nextick-args/-/process-nextick-args-2.0.1.tgz",
      "integrity": "sha512-3ouUOpQhtgrbOa17J7+uxOTpITYWaGP7/AhoR3+A+/1e9skrzelGi/dXzEYyvbxubEF6Wn2ypscTKiKJFFn1ag==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/progress": {
      "version": "2.0.3",
      "resolved": "https://registry.npmjs.org/progress/-/progress-2.0.3.tgz",
      "integrity": "sha512-7PiHtLll5LdnKIMw100I+8xJXR5gW2QwWYkT6iJva0bXitZKa/XMrSbdmg3r2Xnaidz9Qumd0VPaMrZlF9V9sA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.4.0"
      }
    },
    "node_modules/promise-retry": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/promise-retry/-/promise-retry-2.0.1.tgz",
      "integrity": "sha512-y+WKFlBR8BGXnsNlIHFGPZmyDf3DFMoLhaflAnyZgV6rG6xu+JwesTo2Q9R6XwYmtmwAFCkAk3e35jEdoeh/3g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "err-code": "^2.0.2",
        "retry": "^0.12.0"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/proper-lockfile": {
      "version": "4.1.2",
      "resolved": "https://registry.npmjs.org/proper-lockfile/-/proper-lockfile-4.1.2.tgz",
      "integrity": "sha512-TjNPblN4BwAWMXU8s9AEz4JmQxnD1NNL7bNOY/AKUzyamc379FWASUhc/K1pL2noVb+XmZKLL68cjzLsiOAMaA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "graceful-fs": "^4.2.4",
        "retry": "^0.12.0",
        "signal-exit": "^3.0.2"
      }
    },
    "node_modules/pump": {
      "version": "3.0.4",
      "resolved": "https://registry.npmjs.org/pump/-/pump-3.0.4.tgz",
      "integrity": "sha512-VS7sjc6KR7e1ukRFhQSY5LM2uBWAUPiOPa/A3mkKmiMwSmRFUITt0xuj+/lesgnCv+dPIEYlkzrcyXgquIHMcA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "end-of-stream": "^1.1.0",
        "once": "^1.3.1"
      }
    },
    "node_modules/pvtsutils": {
      "version": "1.3.6",
      "resolved": "https://registry.npmjs.org/pvtsutils/-/pvtsutils-1.3.6.tgz",
      "integrity": "sha512-PLgQXQ6H2FWCaeRak8vvk1GW462lMxB5s3Jm673N82zI4vqtVUPuZdffdZbPDFRoU8kAhItWFtPCWiPpp4/EDg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "tslib": "^2.8.1"
      }
    },
    "node_modules/pvutils": {
      "version": "1.2.0",
      "resolved": "https://registry.npmjs.org/pvutils/-/pvutils-1.2.0.tgz",
      "integrity": "sha512-BbubeCEyTuQjVMakvJQ/Sxbc93F2pwmbsxONT/ZRrwU7Ua38d8unYTwXpTVLAKJ4BDuH9IGztCjQcd/N/39Dvg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=16.0.0"
      }
    },
    "node_modules/quick-lru": {
      "version": "5.1.1",
      "resolved": "https://registry.npmjs.org/quick-lru/-/quick-lru-5.1.1.tgz",
      "integrity": "sha512-WuyALRjWPDGtt/wzJiadO5AXY+8hZ80hVpe6MyivgraREW751X3SbhRvG3eLKOYN+8VEvqLcf3wdnt44Z4S4SA==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/read-binary-file-arch": {
      "version": "1.0.6",
      "resolved": "https://registry.npmjs.org/read-binary-file-arch/-/read-binary-file-arch-1.0.6.tgz",
      "integrity": "sha512-BNg9EN3DD3GsDXX7Aa8O4p92sryjkmzYYgmgTAc6CA4uGLEDzFfxOxugu21akOxpcXHiEgsYkC6nPsQvLLLmEg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "debug": "^4.3.4"
      },
      "bin": {
        "read-binary-file-arch": "cli.js"
      }
    },
    "node_modules/readable-stream": {
      "version": "2.3.8",
      "resolved": "https://registry.npmjs.org/readable-stream/-/readable-stream-2.3.8.tgz",
      "integrity": "sha512-8p0AUk4XODgIewSi0l8Epjs+EVnWiK7NoDIEGU0HhE7+ZyY8D1IMY7odu5lRrFXGg71L15KG8QrPmum45RTtdA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "core-util-is": "~1.0.0",
        "inherits": "~2.0.3",
        "isarray": "~1.0.0",
        "process-nextick-args": "~2.0.0",
        "safe-buffer": "~5.1.1",
        "string_decoder": "~1.1.1",
        "util-deprecate": "~1.0.1"
      }
    },
    "node_modules/require-directory": {
      "version": "2.1.1",
      "resolved": "https://registry.npmjs.org/require-directory/-/require-directory-2.1.1.tgz",
      "integrity": "sha512-fGxEI7+wsG9xrvdjsrlmL22OMTTiHRwAMroiEeMgq8gzoLC/PQr7RsRDSTLUg/bZAZtF+TVIkHc6/4RIKrui+Q==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/require-from-string": {
      "version": "2.0.2",
      "resolved": "https://registry.npmjs.org/require-from-string/-/require-from-string-2.0.2.tgz",
      "integrity": "sha512-Xf0nWe6RseziFMu+Ap9biiUbmplq6S9/p+7w7YXP/JBHhrUDDUhwa+vANyubuqfZWTveU//DYVGsDG7RKL/vEw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/resedit": {
      "version": "1.7.2",
      "resolved": "https://registry.npmjs.org/resedit/-/resedit-1.7.2.tgz",
      "integrity": "sha512-vHjcY2MlAITJhC0eRD/Vv8Vlgmu9Sd3LX9zZvtGzU5ZImdTN3+d6e/4mnTyV8vEbyf1sgNIrWxhWlrys52OkEA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "pe-library": "^0.4.1"
      },
      "engines": {
        "node": ">=12",
        "npm": ">=6"
      },
      "funding": {
        "type": "github",
        "url": "https://github.com/sponsors/jet2jet"
      }
    },
    "node_modules/resolve-alpn": {
      "version": "1.2.1",
      "resolved": "https://registry.npmjs.org/resolve-alpn/-/resolve-alpn-1.2.1.tgz",
      "integrity": "sha512-0a1F4l73/ZFZOakJnQ3FvkJ2+gSTQWz/r2KE5OdDY0TxPm5h4GkqkWWfM47T7HsbnOtcJVEF4epCVy6u7Q3K+g==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/responselike": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/responselike/-/responselike-2.0.1.tgz",
      "integrity": "sha512-4gl03wn3hj1HP3yzgdI7d3lCkF95F21Pz4BPGvKHinyQzALR5CapwC8yIi0Rh58DEMQ/SguC03wFj2k0M/mHhw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "lowercase-keys": "^2.0.0"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/retry": {
      "version": "0.12.0",
      "resolved": "https://registry.npmjs.org/retry/-/retry-0.12.0.tgz",
      "integrity": "sha512-9LkiTwjUh6rT555DtE9rTX+BKByPfrMzEAtnlEtdEwr3Nkffwiihqe2bWADg+OQRjt9gl6ICdmB/ZFDCGAtSow==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 4"
      }
    },
    "node_modules/rimraf": {
      "version": "2.6.3",
      "resolved": "https://registry.npmjs.org/rimraf/-/rimraf-2.6.3.tgz",
      "integrity": "sha512-mwqeW5XsA2qAejG46gYdENaxXjx9onRNCfn7L0duuP4hCuTIi/QO7PDK07KJfp1d+izWPrzEJDcSqBa0OZQriA==",
      "deprecated": "Rimraf versions prior to v4 are no longer supported",
      "dev": true,
      "license": "ISC",
      "peer": true,
      "dependencies": {
        "glob": "^7.1.3"
      },
      "bin": {
        "rimraf": "bin.js"
      }
    },
    "node_modules/roarr": {
      "version": "2.15.4",
      "resolved": "https://registry.npmjs.org/roarr/-/roarr-2.15.4.tgz",
      "integrity": "sha512-CHhPh+UNHD2GTXNYhPWLnU8ONHdI+5DI+4EYIAOaiD63rHeYlZvyh8P+in5999TTSFgUYuKUAjzRI4mdh/p+2A==",
      "dev": true,
      "license": "BSD-3-Clause",
      "optional": true,
      "dependencies": {
        "boolean": "^3.0.1",
        "detect-node": "^2.0.4",
        "globalthis": "^1.0.1",
        "json-stringify-safe": "^5.0.1",
        "semver-compare": "^1.0.0",
        "sprintf-js": "^1.1.2"
      },
      "engines": {
        "node": ">=8.0"
      }
    },
    "node_modules/safe-buffer": {
      "version": "5.1.2",
      "resolved": "https://registry.npmjs.org/safe-buffer/-/safe-buffer-5.1.2.tgz",
      "integrity": "sha512-Gd2UZBJDkXlY7GbJxfsE8/nvKkUEU1G38c1siN6QP6a9PT9MmHB8GnpscSmMJSoF8LOIrt8ud/wPtojys4G6+g==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/sanitize-filename": {
      "version": "1.6.4",
      "resolved": "https://registry.npmjs.org/sanitize-filename/-/sanitize-filename-1.6.4.tgz",
      "integrity": "sha512-9ZyI08PsvdQl2r/bBIGubpVdR3RR9sY6RDiWFPreA21C/EFlQhmgo20UZlNjZMMZNubusLhAQozkA0Od5J21Eg==",
      "dev": true,
      "license": "WTFPL OR ISC",
      "dependencies": {
        "truncate-utf8-bytes": "^1.0.0"
      }
    },
    "node_modules/sax": {
      "version": "1.6.1",
      "resolved": "https://registry.npmjs.org/sax/-/sax-1.6.1.tgz",
      "integrity": "sha512-42tBVwLWnaQvW5zc4HbZrTuWccECCZfBi92FDuwtqxasH+JbPB3/FOKb1m222K42R4WxuxzzMsTswfzgtSu64Q==",
      "dev": true,
      "license": "BlueOak-1.0.0",
      "engines": {
        "node": ">=11.0.0"
      }
    },
    "node_modules/semver": {
      "version": "7.8.5",
      "resolved": "https://registry.npmjs.org/semver/-/semver-7.8.5.tgz",
      "integrity": "sha512-Y7/KDsb8LjooZpwaqGyulO6DQlksgCncchHGk+sZIY4SBvUocMBEFH5Ur1fI4dV+Jvl0w6cjvucaIi40puRioA==",
      "dev": true,
      "license": "ISC",
      "bin": {
        "semver": "bin/semver.js"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/semver-compare": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/semver-compare/-/semver-compare-1.0.0.tgz",
      "integrity": "sha512-YM3/ITh2MJ5MtzaM429anh+x2jiLVjqILF4m4oyQB18W7Ggea7BfqdH/wGMK7dDiMghv/6WG7znWMwUDzJiXow==",
      "dev": true,
      "license": "MIT",
      "optional": true
    },
    "node_modules/serialize-error": {
      "version": "7.0.1",
      "resolved": "https://registry.npmjs.org/serialize-error/-/serialize-error-7.0.1.tgz",
      "integrity": "sha512-8I8TjW5KMOKsZQTvoxjuSIa7foAwPWGOts+6o7sgjz41/qMD9VQHEDxi6PBvK2l0MXUmqZyNpUK+T2tQaaElvw==",
      "dev": true,
      "license": "MIT",
      "optional": true,
      "dependencies": {
        "type-fest": "^0.13.1"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/shebang-command": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/shebang-command/-/shebang-command-2.0.0.tgz",
      "integrity": "sha512-kHxr2zZpYtdmrN1qDjrrX/Z1rR1kG8Dx+gkpK1G4eXmvXswmcE1hTWBWYUzlraYw1/yZp6YuDY77YtvbN0dmDA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "shebang-regex": "^3.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/shebang-regex": {
      "version": "3.0.0",
      "resolved": "https://registry.npmjs.org/shebang-regex/-/shebang-regex-3.0.0.tgz",
      "integrity": "sha512-7++dFhtcx3353uBaq8DDR4NuxBetBzC7ZQOhmTQInHEd6bSrXdiEyzCvG07Z44UYdLShWUyXt5M/yhz8ekcb1A==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/signal-exit": {
      "version": "3.0.7",
      "resolved": "https://registry.npmjs.org/signal-exit/-/signal-exit-3.0.7.tgz",
      "integrity": "sha512-wnD2ZE+l+SPC/uoS0vXeE9L1+0wuaMqKlfz9AMUo38JsyLSBWSFcHR1Rri62LZc12vLr1gb3jl7iwQhgwpAbGQ==",
      "dev": true,
      "license": "ISC"
    },
    "node_modules/simple-update-notifier": {
      "version": "2.0.0",
      "resolved": "https://registry.npmjs.org/simple-update-notifier/-/simple-update-notifier-2.0.0.tgz",
      "integrity": "sha512-a2B9Y0KlNXl9u/vsW6sTIu9vGEpfKu2wRV6l1H3XEas/0gUIzGzBoP/IouTcUQbm9JWZLH3COxyn03TYlFax6w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "semver": "^7.5.3"
      },
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/source-map": {
      "version": "0.6.1",
      "resolved": "https://registry.npmjs.org/source-map/-/source-map-0.6.1.tgz",
      "integrity": "sha512-UjgapumWlbMhkBgzT7Ykc5YXUT46F0iKu8SGXq0bcwP5dz/h0Plj6enJqjz1Zbq2l5WaqYnrVbwWOWMyF3F47g==",
      "dev": true,
      "license": "BSD-3-Clause",
      "engines": {
        "node": ">=0.10.0"
      }
    },
    "node_modules/source-map-support": {
      "version": "0.5.21",
      "resolved": "https://registry.npmjs.org/source-map-support/-/source-map-support-0.5.21.tgz",
      "integrity": "sha512-uBHU3L3czsIyYXKX88fdrGovxdSCoTGDRZ6SYXtSRxLZUzHg5P/66Ht6uoUlHu9EZod+inXhKo3qQgwXUT/y1w==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "buffer-from": "^1.0.0",
        "source-map": "^0.6.0"
      }
    },
    "node_modules/sprintf-js": {
      "version": "1.1.3",
      "resolved": "https://registry.npmjs.org/sprintf-js/-/sprintf-js-1.1.3.tgz",
      "integrity": "sha512-Oo+0REFV59/rz3gfJNKQiBlwfHaSESl1pcGyABQsnnIfWOFt6JNj5gCog2U6MLZ//IGYD+nA8nI+mTShREReaA==",
      "dev": true,
      "license": "BSD-3-Clause",
      "optional": true
    },
    "node_modules/stat-mode": {
      "version": "1.0.0",
      "resolved": "https://registry.npmjs.org/stat-mode/-/stat-mode-1.0.0.tgz",
      "integrity": "sha512-jH9EhtKIjuXZ2cWxmXS8ZP80XyC3iasQxMDV8jzhNJpfDb7VbQLVW4Wvsxz9QZvzV+G4YoSfBUVKDOyxLzi/sg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 6"
      }
    },
    "node_modules/string_decoder": {
      "version": "1.1.1",
      "resolved": "https://registry.npmjs.org/string_decoder/-/string_decoder-1.1.1.tgz",
      "integrity": "sha512-n/ShnvDi6FHbbVfviro+WojiFzv+s8MPMHBczVePfUpDJLwoLT0ht1l4YwBCbi8pJAveEEdnkHyPyTP/mzRfwg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "safe-buffer": "~5.1.0"
      }
    },
    "node_modules/string-width": {
      "version": "4.2.3",
      "resolved": "https://registry.npmjs.org/string-width/-/string-width-4.2.3.tgz",
      "integrity": "sha512-wKyQRQpjJ0sIp62ErSZdGsjMJWsap5oRNihHhu6G7JVO/9jIB6UyevL+tXuOqrng8j/cxKTWyWUwvSTriiZz/g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "emoji-regex": "^8.0.0",
        "is-fullwidth-code-point": "^3.0.0",
        "strip-ansi": "^6.0.1"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/strip-ansi": {
      "version": "6.0.1",
      "resolved": "https://registry.npmjs.org/strip-ansi/-/strip-ansi-6.0.1.tgz",
      "integrity": "sha512-Y38VPSHcqkFrCpFnQ9vuSXmquuv5oXOKpGeT6aGrr3o3Gc9AlVa6JBfUSOCnbxGGZF+/0ooI7KrPuUSztUdU5A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "ansi-regex": "^5.0.1"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/sumchecker": {
      "version": "3.0.1",
      "resolved": "https://registry.npmjs.org/sumchecker/-/sumchecker-3.0.1.tgz",
      "integrity": "sha512-MvjXzkz/BOfyVDkG0oFOtBxHX2u3gKbMHIF/dXblZsgD3BWOFLmHovIpZY7BykJdAjcqRCBi1WYBNdEC9yI7vg==",
      "dev": true,
      "license": "Apache-2.0",
      "dependencies": {
        "debug": "^4.1.0"
      },
      "engines": {
        "node": ">= 8.0"
      }
    },
    "node_modules/supports-color": {
      "version": "7.2.0",
      "resolved": "https://registry.npmjs.org/supports-color/-/supports-color-7.2.0.tgz",
      "integrity": "sha512-qpCAvRl9stuOHveKsn7HncJRvv501qIacKzQlO/+Lwxc9+0q2wLyv4Dfvt80/DPn2pqOBsJdDiogXGR9+OvwRw==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "has-flag": "^4.0.0"
      },
      "engines": {
        "node": ">=8"
      }
    },
    "node_modules/tar": {
      "version": "7.5.22",
      "resolved": "https://registry.npmjs.org/tar/-/tar-7.5.22.tgz",
      "integrity": "sha512-MFO/QzvtAOmJbkhOaCTvbGcFN9L9b+JunIsDwaKljSOdcLMea3NJ1k9Usz/rjdfSXTq4dfzfeS7W4p4YOAAHeA==",
      "dev": true,
      "license": "BlueOak-1.0.0",
      "dependencies": {
        "@isaacs/fs-minipass": "^4.0.0",
        "chownr": "^3.0.0",
        "minipass": "^7.1.2",
        "minizlib": "^3.1.0",
        "yallist": "^5.0.0"
      },
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/tar/node_modules/yallist": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/yallist/-/yallist-5.0.0.tgz",
      "integrity": "sha512-YgvUTfwqyc7UXVMrB+SImsVYSmTS8X/tSrtdNZMImM+n7+QTriRXyXim0mBrTXNeqzVF0KWGgHPeiyViFFrNDw==",
      "dev": true,
      "license": "BlueOak-1.0.0",
      "engines": {
        "node": ">=18"
      }
    },
    "node_modules/temp": {
      "version": "0.9.4",
      "resolved": "https://registry.npmjs.org/temp/-/temp-0.9.4.tgz",
      "integrity": "sha512-yYrrsWnrXMcdsnu/7YMYAofM1ktpL5By7vZhf15CrXijWWrEYZks5AXBudalfSWJLlnen/QUJUB5aoB0kqZUGA==",
      "dev": true,
      "license": "MIT",
      "peer": true,
      "dependencies": {
        "mkdirp": "^0.5.1",
        "rimraf": "~2.6.2"
      },
      "engines": {
        "node": ">=6.0.0"
      }
    },
    "node_modules/temp-file": {
      "version": "3.4.0",
      "resolved": "https://registry.npmjs.org/temp-file/-/temp-file-3.4.0.tgz",
      "integrity": "sha512-C5tjlC/HCtVUOi3KWVokd4vHVViOmGjtLwIh4MuzPo/nMYTV/p1urt3RnMz2IWXDdKEGJH3k5+KPxtqRsUYGtg==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "async-exit-hook": "^2.0.1",
        "fs-extra": "^10.0.0"
      }
    },
    "node_modules/three": {
      "version": "0.186.1",
      "resolved": "https://registry.npmjs.org/three/-/three-0.186.1.tgz",
      "integrity": "sha512-blFeqb49wRCSGUGj7gtpfnSGHy2lwDk94RhUmS1c/hTby70kvChbWpkJ4Pm1390LqzzvTmzgXKHPEafJwCb8jA==",
      "license": "MIT"
    },
    "node_modules/tiny-async-pool": {
      "version": "1.3.0",
      "resolved": "https://registry.npmjs.org/tiny-async-pool/-/tiny-async-pool-1.3.0.tgz",
      "integrity": "sha512-01EAw5EDrcVrdgyCLgoSPvqznC0sVxDSVeiOz09FUpjh71G79VCqneOr+xvt7T1r76CF6ZZfPjHorN2+d+3mqA==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "semver": "^5.5.0"
      }
    },
    "node_modules/tiny-async-pool/node_modules/semver": {
      "version": "5.7.2",
      "resolved": "https://registry.npmjs.org/semver/-/semver-5.7.2.tgz",
      "integrity": "sha512-cBznnQ9KjJqU67B52RMC65CMarK2600WFnbkcaiwWq3xy/5haFJlshgnpjovMVJ+Hff49d8GEn0b87C5pDQ10g==",
      "dev": true,
      "license": "ISC",
      "bin": {
        "semver": "bin/semver"
      }
    },
    "node_modules/tinyglobby": {
      "version": "0.2.17",
      "resolved": "https://registry.npmjs.org/tinyglobby/-/tinyglobby-0.2.17.tgz",
      "integrity": "sha512-wXR/dYpcqKmfWpEdZjiKJOwCNFndD0DMnrW/cYjVGttEkBfVgcLFHoNrlj47mjOVic9yyNu65alsgF4NQyTa2g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "fdir": "^6.5.0",
        "picomatch": "^4.0.4"
      },
      "engines": {
        "node": ">=12.0.0"
      },
      "funding": {
        "url": "https://github.com/sponsors/SuperchupuDev"
      }
    },
    "node_modules/tmp": {
      "version": "0.2.7",
      "resolved": "https://registry.npmjs.org/tmp/-/tmp-0.2.7.tgz",
      "integrity": "sha512-e0votIpp4Uo2AJYSzVHV6xCcawuiez3DzqDAbrTc3YxBkplN6e+dM13ZeIcZnDg/QpSuU2zfZ3rzwY8ukEnaXw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=14.14"
      }
    },
    "node_modules/tmp-promise": {
      "version": "3.0.3",
      "resolved": "https://registry.npmjs.org/tmp-promise/-/tmp-promise-3.0.3.tgz",
      "integrity": "sha512-RwM7MoPojPxsOBYnyd2hy0bxtIlVrihNs9pj5SUvY8Zz1sQcQG2tG1hSr8PDxfgEB8RNKDhqbIlroIarSNDNsQ==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "tmp": "^0.2.0"
      }
    },
    "node_modules/truncate-utf8-bytes": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/truncate-utf8-bytes/-/truncate-utf8-bytes-1.0.2.tgz",
      "integrity": "sha512-95Pu1QXQvruGEhv62XCMO3Mm90GscOCClvrIUwCM0PYOXK3kaF3l3sIHxx71ThJfcbM2O5Au6SO3AWCSEfW4mQ==",
      "dev": true,
      "license": "WTFPL",
      "dependencies": {
        "utf8-byte-length": "^1.0.1"
      }
    },
    "node_modules/tslib": {
      "version": "2.8.1",
      "resolved": "https://registry.npmjs.org/tslib/-/tslib-2.8.1.tgz",
      "integrity": "sha512-oJFu94HQb+KVduSUQL7wnpmqnfmLsOA/nAh6b6EH0wCEoK0/mPeXU6c3wKDV83MkOuHPRHtSXKKU99IBazS/2w==",
      "dev": true,
      "license": "0BSD"
    },
    "node_modules/type-fest": {
      "version": "0.13.1",
      "resolved": "https://registry.npmjs.org/type-fest/-/type-fest-0.13.1.tgz",
      "integrity": "sha512-34R7HTnG0XIJcBSn5XhDd7nNFPRcXYRZrBB2O2jdKqYODldSzBAqzsWoZYYvduky73toYS/ESqxPvkDf/F0XMg==",
      "dev": true,
      "license": "(MIT OR CC0-1.0)",
      "optional": true,
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    },
    "node_modules/undici": {
      "version": "7.30.0",
      "resolved": "https://registry.npmjs.org/undici/-/undici-7.30.0.tgz",
      "integrity": "sha512-dkrQXeHSaoamnItlYbmzG0wFYrM0ZwDxCIg0A7aKjTyyhh9svRzCNFEzV+Vm05/yehjCzjDZ31KXfGEjYSztDQ==",
      "dev": true,
      "license": "MIT",
      "optional": true,
      "engines": {
        "node": ">=20.18.1"
      }
    },
    "node_modules/undici-types": {
      "version": "7.24.6",
      "resolved": "https://registry.npmjs.org/undici-types/-/undici-types-7.24.6.tgz",
      "integrity": "sha512-WRNW+sJgj5OBN4/0JpHFqtqzhpbnV0GuB+OozA9gCL7a993SmU+1JBZCzLNxYsbMfIeDL+lTsphD5jN5N+n0zg==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/universalify": {
      "version": "2.0.1",
      "resolved": "https://registry.npmjs.org/universalify/-/universalify-2.0.1.tgz",
      "integrity": "sha512-gptHNQghINnc/vTGIk0SOFGFNXw7JVrlRUtConJRlvaw6DuX0wO5Jeko9sWrMBhh+PsYAZ7oXAiOnf/UKogyiw==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">= 10.0.0"
      }
    },
    "node_modules/unzipper": {
      "version": "0.12.5",
      "resolved": "https://registry.npmjs.org/unzipper/-/unzipper-0.12.5.tgz",
      "integrity": "sha512-tXYOi9R57Uj/2Z25SOs5RRSzq886MBQj2gY8dPL+xl/kv6s6SvByoKfAtvfVeEuhntWDgjd2o9p2lb4TVPAz0A==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "bluebird": "~3.7.2",
        "duplexer2": "~0.1.4",
        "fs-extra": "11.3.1",
        "graceful-fs": "^4.2.2",
        "node-int64": "^0.4.0"
      }
    },
    "node_modules/unzipper/node_modules/fs-extra": {
      "version": "11.3.1",
      "resolved": "https://registry.npmjs.org/fs-extra/-/fs-extra-11.3.1.tgz",
      "integrity": "sha512-eXvGGwZ5CL17ZSwHWd3bbgk7UUpF6IFHtP57NYYakPvHOs8GDgDe5KJI36jIJzDkJ6eJjuzRA8eBQb6SkKue0g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "graceful-fs": "^4.2.0",
        "jsonfile": "^6.0.1",
        "universalify": "^2.0.0"
      },
      "engines": {
        "node": ">=14.14"
      }
    },
    "node_modules/utf8-byte-length": {
      "version": "1.0.5",
      "resolved": "https://registry.npmjs.org/utf8-byte-length/-/utf8-byte-length-1.0.5.tgz",
      "integrity": "sha512-Xn0w3MtiQ6zoz2vFyUVruaCL53O/DwUvkEeOvj+uulMm0BkUGYWmBYVyElqZaSLhY6ZD0ulfU3aBra2aVT4xfA==",
      "dev": true,
      "license": "(WTFPL OR MIT)"
    },
    "node_modules/util-deprecate": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/util-deprecate/-/util-deprecate-1.0.2.tgz",
      "integrity": "sha512-EPD5q1uXyFxJpCrLnCc1nHnq3gOa6DZBocAIiI2TaSCA7VCJ1UJDMagCzIkXNsUYfD1daK//LTEQ8xiIbrHtcw==",
      "dev": true,
      "license": "MIT"
    },
    "node_modules/webcrypto-core": {
      "version": "1.9.2",
      "resolved": "https://registry.npmjs.org/webcrypto-core/-/webcrypto-core-1.9.2.tgz",
      "integrity": "sha512-gsXecm82UQNlTBURJGuqOWy1Ww08S3kZUcr3aOJS02Pk0xLtkfeUAVC0u0xhgdonFme80edSJUIJyuvL/7250Q==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "@peculiar/asn1-schema": "^2.7.0",
        "@peculiar/json-schema": "^1.1.12",
        "@peculiar/utils": "^2.0.2",
        "asn1js": "^3.0.10",
        "tslib": "^2.8.1"
      }
    },
    "node_modules/which": {
      "version": "5.0.0",
      "resolved": "https://registry.npmjs.org/which/-/which-5.0.0.tgz",
      "integrity": "sha512-JEdGzHwwkrbWoGOlIHqQ5gtprKGOenpDHpxE9zVR1bWbOtYRyPPHMe9FaP6x61CmNaTThSkb0DAJte5jD+DmzQ==",
      "dev": true,
      "license": "ISC",
      "dependencies": {
        "isexe": "^3.1.1"
      },
      "bin": {
        "node-which": "bin/which.js"
      },
      "engines": {
        "node": "^18.17.0 || >=20.5.0"
      }
    },
    "node_modules/wrap-ansi": {
      "version": "7.0.0",
      "resolved": "https://registry.npmjs.org/wrap-ansi/-/wrap-ansi-7.0.0.tgz",
      "integrity": "sha512-YVGIj2kamLSTxw6NsZjoBxfSwsn0ycdesmc4p+Q21c5zPuZ1pl+NfxVdxPtdHvmNVOQ6XSYG4AUtyt/Fi7D16Q==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "ansi-styles": "^4.0.0",
        "string-width": "^4.1.0",
        "strip-ansi": "^6.0.0"
      },
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/chalk/wrap-ansi?sponsor=1"
      }
    },
    "node_modules/wrappy": {
      "version": "1.0.2",
      "resolved": "https://registry.npmjs.org/wrappy/-/wrappy-1.0.2.tgz",
      "integrity": "sha512-l4Sp/DRseor9wL6EvV2+TuQn63dMkPjZ/sp9XkghTEbV9KlPS1xUsZ3u7/IQO4wxtcFB4bgpQPRcR3QCvezPcQ==",
      "dev": true,
      "license": "ISC"
    },
    "node_modules/xmlbuilder": {
      "version": "15.1.1",
      "resolved": "https://registry.npmjs.org/xmlbuilder/-/xmlbuilder-15.1.1.tgz",
      "integrity": "sha512-yMqGBqtXyeN1e3TGYvgNgDVZ3j84W4cwkOXQswghol6APgZWaff9lnbvN7MHYJOiXsvGPXtjTYJEiC9J2wv9Eg==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=8.0"
      }
    },
    "node_modules/y18n": {
      "version": "5.0.8",
      "resolved": "https://registry.npmjs.org/y18n/-/y18n-5.0.8.tgz",
      "integrity": "sha512-0pfFzegeDWJHJIAmTLRP2DwHjdF5s7jo9tuztdQxAhINCdvS+3nGINqPd00AphqJR/0LhANUS6/+7SCb98YOfA==",
      "dev": true,
      "license": "ISC",
      "engines": {
        "node": ">=10"
      }
    },
    "node_modules/yallist": {
      "version": "4.0.0",
      "resolved": "https://registry.npmjs.org/yallist/-/yallist-4.0.0.tgz",
      "integrity": "sha512-3wdGidZyq5PB084XLES5TpOSRA3wjXAlIWMhum2kRcv/41Sn2emQ0dycQW4uZXLejwKvg6EsvbdlVL+FYEct7A==",
      "dev": true,
      "license": "ISC"
    },
    "node_modules/yargs": {
      "version": "17.7.3",
      "resolved": "https://registry.npmjs.org/yargs/-/yargs-17.7.3.tgz",
      "integrity": "sha512-GZtjxm/J/4TSxuL3FNYjCmLktBTnIw/rVmKSIyKeYAZpmJB2ig9VauCC5xsa82GNKVKDAqpOn3KVzNt0zmrU0g==",
      "dev": true,
      "license": "MIT",
      "dependencies": {
        "cliui": "^8.0.1",
        "escalade": "^3.1.1",
        "get-caller-file": "^2.0.5",
        "require-directory": "^2.1.1",
        "string-width": "^4.2.3",
        "y18n": "^5.0.5",
        "yargs-parser": "^21.1.1"
      },
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/yargs-parser": {
      "version": "21.1.1",
      "resolved": "https://registry.npmjs.org/yargs-parser/-/yargs-parser-21.1.1.tgz",
      "integrity": "sha512-tVpsJW7DdjecAiFpbIB1e3qxIQsE6NoPc5/eTdrbbIC4h0LVsWhnoa3g+m2HclBIujHzsxZ4VJVA+GUuc2/LBw==",
      "dev": true,
      "license": "ISC",
      "engines": {
        "node": ">=12"
      }
    },
    "node_modules/yocto-queue": {
      "version": "0.1.0",
      "resolved": "https://registry.npmjs.org/yocto-queue/-/yocto-queue-0.1.0.tgz",
      "integrity": "sha512-rVksvsnNCdJ/ohGc6xgPwyN8eheCxsiLM8mxuE/t/mOVqJewPuO1miLpTHQiRgTKCLexL4MeAFVagts7HmNZ2Q==",
      "dev": true,
      "license": "MIT",
      "engines": {
        "node": ">=10"
      },
      "funding": {
        "url": "https://github.com/sponsors/sindresorhus"
      }
    }
  }
}

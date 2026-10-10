import AppKit
import SwiftUI

enum PetQuickAction: String, CaseIterable {
    case petting, agenda, focus, animations, notes, openPanel, companions
    var title: String {
        switch self {
        case .petting: return "Acariciar"
        case .agenda: return "Agenda"
        case .focus: return "Concentración"
        case .animations: return "Animaciones"
        case .notes: return "Notas"
        case .openPanel: return "Abrir panel"
        case .companions: return "Cambiar Pokémon"
        }
    }
    var symbol: String {
        switch self {
        case .petting: return "heart.fill"
        case .agenda: return "calendar"
        case .focus: return "timer"
        case .animations: return "pawprint.fill"
        case .notes: return "note.text"
        case .openPanel: return "square.grid.2x2.fill"
        case .companions: return "arrow.triangle.2.circlepath"
        }
    }
    var tab: Int? {
        switch self {
        case .agenda: return 0
        case .focus: return 2
        case .animations: return 4
        case .notes: return 5
        case .openPanel: return -1
        case .petting: return nil
        case .companions: return 3
        }
    }
    var detailHeight: Double { self == .companions ? 372 : self == .notes ? 400 : self == .animations ? 360 : self == .agenda ? 310 : 252 }
}

@MainActor final class PetQuickMenuState: ObservableObject {
    @Published var selected: PetQuickAction?
    @Published var character: PetCharacter = .arcanine
}

/// The empty middle of the semicircle does not become an invisible rectangular window.
final class PetQuickHostingView: NSHostingView<PetQuickMenuView> {
    override var isOpaque: Bool { false }
    func containsControl(_ point: NSPoint) -> Bool {
        QuickMenuLayout.containsControl(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return containsControl(local) ? super.hitTest(point) : nil
    }
}

private struct PetShortcutButton: View {
    @Environment(\.petTheme) private var theme
    let action: PetQuickAction
    let selected: Bool
    let invoke: () -> Void
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button(action: invoke) {
            VStack(spacing: 6) {
                Image(systemName: action.symbol).font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(selected || action == .petting ? .white : theme.red)
                    .frame(width: 50, height: 50)
                    .background(selected || action == .petting ? theme.red : theme.card)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(theme.gold.opacity(0.85), lineWidth: 2))
                    .shadow(color: theme.ink.opacity(0.17), radius: 3, y: 2)
                Text(action.title).font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(theme.paper.opacity(0.98)).clipShape(Capsule())
            }.frame(width: 94, height: 76)
                .contentShape(RoundedRectangle(cornerRadius: 18))
                .scaleEffect(hovering && !reduceMotion ? 1.06 : 1)
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
            .accessibilityLabel(action.title).help(action == .openPanel ? "Abrir todas las opciones de PokéDesk" : action.title)
    }
}

struct PetQuickMenuView: View {
    private var theme: PetTheme { PetTheme(character: state.character) }
    @ObservedObject var state: PetQuickMenuState
    let onSelect: (PetQuickAction) -> Void
    let onClose: () -> Void
    private var arc: Path {
        Path { path in
            for degrees in stride(from: 166.0, through: 14.0, by: -2) {
                let angle = degrees * .pi / 180
                let point = CGPoint(x: QuickMenuLayout.width / 2 + QuickMenuLayout.radiusX * cos(angle), y: 143 - 104 * sin(angle))
                if degrees == 166 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            arc.stroke(theme.line, style: StrokeStyle(lineWidth: 58, lineCap: .round))
                .shadow(color: .black.opacity(0.10), radius: 3, y: 2).allowsHitTesting(false)
            arc.stroke(theme.paper.opacity(0.98), style: StrokeStyle(lineWidth: 54, lineCap: .round)).allowsHitTesting(false)
            ForEach(Array(PetQuickAction.allCases.filter { $0 != .companions }.enumerated()), id: \.element.rawValue) { index, action in
                let point = QuickMenuLayout.buttonCenter(index)
                PetShortcutButton(action: action, selected: state.selected == action) { onSelect(action) }
                    .position(x: point.x, y: point.y)
            }
            Button { onSelect(.companions) } label: {
                Label("Cambiar Pokémon", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(state.selected == .companions ? .white : theme.red)
                    .frame(width: 166, height: 34)
                    .background(state.selected == .companions ? theme.red : theme.paper)
                    .clipShape(Capsule()).overlay(Capsule().stroke(theme.gold, lineWidth: 1.5))
            }.buttonStyle(.plain).position(x: QuickMenuLayout.width / 2, y: 126)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.muted).frame(width: 26, height: 26)
                    .background(theme.paper).clipShape(Circle())
                    .overlay(Circle().stroke(theme.line, lineWidth: 1))
            }.buttonStyle(.plain).position(x: QuickMenuLayout.width / 2, y: 164)
                .accessibilityLabel("Cerrar accesos rápidos").help("Cerrar accesos · Escape")
        }.frame(width: QuickMenuLayout.width, height: QuickMenuLayout.height)
            .preferredColorScheme(.light).environment(\.petTheme, theme)
    }
}

struct PetQuickDetailView: View {
    private var theme: PetTheme { PetTheme(character: model.settings.character) }
    @ObservedObject var model: PetModel
    let action: PetQuickAction
    let onExpand: () -> Void
    let onClose: () -> Void
    let onTimer: (Int) -> Void
    let onAnimation: (ArcanineClip) -> Void
    let onCharacter: (PetCharacter) -> Void
    private var clips: [ArcanineClip] { [.petting, .sit] + model.settings.character.clips.filter { $0 != .petting && $0 != .sit } }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: action.symbol).foregroundStyle(theme.red)
                Text(action.title).font(.system(size: 16, weight: .bold, design: .rounded))
                Spacer()
                PokedexIconButton(symbol: "xmark", label: "Cerrar \(action.title)") { onClose() }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if action == .companions { PetCharacterChooser(selected: model.settings.character, onSelect: onCharacter) }
                    if action == .agenda { agenda }
                    if action == .focus { focus }
                    if action == .animations { animations }
                    if action == .notes { PetNotesQuickView(model: model) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action == .focus ? "Elegir otro tiempo en el panel" : "Ver \(action.title.lowercased()) en el panel", action: onExpand)
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.red).buttonStyle(.plain)
        }.padding(16).foregroundStyle(theme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.paper).clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.line, lineWidth: 1.5))
            .tint(theme.red).buttonStyle(PokedexButtonStyle()).controlSize(.small).preferredColorScheme(.light).environment(\.petTheme, theme)
    }
    private var agenda: some View {
        VStack(alignment: .leading, spacing: 10) {
            let meetings = Array(model.meetings.filter { !$0.allDay && $0.end > model.clockNow }.prefix(3))
            if meetings.isEmpty {
                let ready = model.calendarConnected
                Label(ready ? "No hay reuniones próximas" : "Tu agenda aún no está lista", systemImage: ready ? "sun.max" : "calendar.badge.clock")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.calendarMessage)
                    .font(.system(size: 11)).foregroundStyle(theme.muted)
            }
            ForEach(meetings) { meeting in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(meeting.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        Text(meeting.start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
                            .font(.system(size: 10)).foregroundStyle(theme.muted)
                    }
                    Spacer(minLength: 0)
                    if let url = meeting.joinURL { Button("Unirme") { model.openMeeting(url) } }
                }.padding(10).background(theme.card).clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }
    private var focus: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let timer = model.settings.focusTimer {
                Text(timer.phase == .finished ? "Foco completado" : timer.display(at: model.clockNow))
                    .font(.system(size: 25, weight: .bold, design: .rounded)).monospacedDigit()
                HStack {
                    if timer.phase != .finished { Button(timer.phase == .paused ? "Reanudar" : "Pausar") { model.pauseOrResumeFocus() } }
                    Button(timer.phase == .finished ? "Listo" : "Cancelar") { model.stopFocus() }
                }
            } else {
                Text("Un rato para concentrarte").font(.system(size: 12)).foregroundStyle(theme.muted)
            }
            HStack(spacing: 7) {
                ForEach([5, 10, 30], id: \.self) { minutes in
                    Button("\(minutes) min") { onTimer(minutes) }.buttonStyle(PokedexButtonStyle(prominent: true))
                }
            }
        }
    }
    private var animations: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 3), spacing: 7) {
            ForEach(clips, id: \.rawValue) { clip in
                Button { onAnimation(clip) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: clip == .petting ? "heart.fill" : clip == .sit ? "pawprint.fill" : "play.fill")
                            .font(.system(size: 13)).foregroundStyle(theme.red)
                        Text(model.settings.character.title(for: clip)).font(.system(size: 10, weight: .semibold, design: .rounded)).lineLimit(2)
                    }.frame(maxWidth: .infinity).frame(height: 55)
                        .background(theme.card).clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.line, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).accessibilityLabel("Reproducir: \(model.settings.character.title(for: clip))")
            }
        }
    }
}

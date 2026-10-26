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
        case .petting: return "heart"
        case .agenda: return "calendar"
        case .focus: return "timer"
        case .animations: return "sparkles"
        case .notes: return "note.text"
        case .openPanel: return "square.grid.2x2"
        case .companions: return "arrow.triangle.2.circlepath"
        }
    }
    var shortTitle: String {
        switch self {
        case .petting: return "Cariño"
        case .focus: return "Foco"
        case .animations: return "Gestos"
        case .openPanel: return "Panel"
        default: return title
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
    @Published var expanded = false
    @Published var interactionReady = false
    @Published var origin = CGPoint(x: QuickMenuLayout.width / 2, y: 270)
    var presentation = 0
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
            VStack(spacing: 7) {
                Image(systemName: action.symbol).font(.system(size: 18, weight: .regular))
                    .foregroundStyle(selected ? theme.red : theme.ink)
                    .frame(width: 46, height: 46)
                    .background(selected || hovering ? theme.accentSoft : theme.paper)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(theme.line.opacity(0.6), lineWidth: 0.5))
                    .shadow(color: theme.ink.opacity(0.10), radius: hovering ? 9 : 6, y: hovering ? 4 : 2)
                Text(action.shortTitle).font(.system(size: 11, weight: .medium))
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .foregroundStyle(theme.ink)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(theme.paper).clipShape(Capsule())
            }.frame(width: 94, height: 76)
                .contentShape(RoundedRectangle(cornerRadius: 18))
                .scaleEffect(hovering && !reduceMotion ? 1.09 : 1)
                .offset(y: hovering && !reduceMotion ? -3 : 0)
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.76), value: hovering)
            .accessibilityLabel(action.title).help(action == .openPanel ? "Abrir todas las opciones de PokéDesk" : action.title)
    }
}

struct PetQuickMenuView: View {
    private var theme: PetTheme { PetTheme(character: state.character) }
    @ObservedObject var state: PetQuickMenuState
    let onSelect: (PetQuickAction) -> Void
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(PetQuickAction.allCases.filter { $0 != .companions }.enumerated()), id: \.element.rawValue) { index, action in
                let point = QuickMenuLayout.buttonCenter(index)
                PetShortcutButton(action: action, selected: state.selected == action) { onSelect(action) }
                    .disabled(!state.interactionReady)
                    .scaleEffect(state.expanded || reduceMotion ? 1 : 0.18)
                    .opacity(state.expanded ? 1 : 0)
                    .position(x: state.expanded || reduceMotion ? point.x : state.origin.x,
                              y: state.expanded || reduceMotion ? point.y : state.origin.y)
                    .animation(reduceMotion ? nil : .spring(response: 0.40, dampingFraction: 0.82).delay(Double(index) * 0.018), value: state.expanded)
            }
            Button { onSelect(.companions) } label: {
                Label("Cambiar Pokémon", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.red)
                    .frame(width: 166, height: 34)
                    .background(state.selected == .companions ? theme.accentSoft : theme.paper)
                    .clipShape(Capsule()).shadow(color: theme.ink.opacity(0.08), radius: 5, y: 2)
            }.buttonStyle(.plain).disabled(!state.interactionReady)
                .scaleEffect(state.expanded ? 1 : 0.3).opacity(state.expanded ? 1 : 0)
                .position(x: state.expanded ? QuickMenuLayout.width / 2 : state.origin.x,
                          y: state.expanded ? 126 : state.origin.y)
                .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85).delay(0.08), value: state.expanded)
            Button(action: onClose) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.muted).frame(width: 26, height: 26)
                    .background(theme.paper).clipShape(Circle())
            }.buttonStyle(.plain).position(x: QuickMenuLayout.width / 2, y: 164)
                .opacity(state.expanded ? 1 : 0)
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
                Text(action.title).font(.system(size: 16, weight: .semibold))
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
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.line, lineWidth: 1))
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
                    .font(.system(size: 25, weight: .semibold)).monospacedDigit()
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
                        Text(model.settings.character.title(for: clip)).font(.system(size: 10, weight: .semibold)).lineLimit(2)
                    }.frame(maxWidth: .infinity).frame(height: 55)
                        .background(theme.card).clipShape(RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.line, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain).accessibilityLabel("Reproducir: \(model.settings.character.title(for: clip))")
            }
        }
    }
}

import SwiftUI
import AppKit

enum ArcanineTheme {
    static let red = Color(red: 0.76, green: 0.17, blue: 0.17)
    static let deepRed = Color(red: 0.56, green: 0.11, blue: 0.12)
    static let fire = Color(red: 0.82, green: 0.33, blue: 0.09)
    static let gold = Color(red: 0.94, green: 0.72, blue: 0.34)
    static let ink = Color(red: 0.22, green: 0.18, blue: 0.15)
    static let muted = Color(red: 0.43, green: 0.38, blue: 0.32)
    static let paper = Color(red: 0.99, green: 0.96, blue: 0.88)
    static let card = Color(red: 1.0, green: 0.99, blue: 0.96)
    static let line = Color(red: 0.82, green: 0.75, blue: 0.63)
    static let blue = Color(red: 0.16, green: 0.43, blue: 0.64)
    static let green = Color(red: 0.17, green: 0.43, blue: 0.29)
}

struct PokedexShape: Shape {
    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: 24, style: .continuous).path(in: rect)
    }
}

struct PokeballMark: View {
    @Environment(\.petTheme) private var theme
    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle().fill(theme.card)
                Rectangle().fill(theme.red).frame(height: side / 2).offset(y: -side / 4)
                Rectangle().fill(theme.ink).frame(height: side * 0.075)
                Circle().fill(theme.card).frame(width: side * 0.32, height: side * 0.32)
                    .overlay(Circle().stroke(theme.ink, lineWidth: side * 0.065))
                Circle().fill(theme.line).frame(width: side * 0.12, height: side * 0.12)
            }
            .frame(width: side, height: side).clipShape(Circle())
            .overlay(Circle().stroke(theme.ink, lineWidth: side * 0.065))
        }
        .accessibilityHidden(true)
    }
}

struct PokedexLens: View {
    @Environment(\.petTheme) private var theme
    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle().fill(LinearGradient(colors: [Color(red: 0.45, green: 0.84, blue: 0.96), theme.blue], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.8)).frame(width: 9, height: 9).offset(x: 9, y: 8)
        }
        .frame(width: 36, height: 36)
        .overlay(Circle().stroke(theme.paper, lineWidth: 3))
        .overlay(Circle().stroke(theme.deepRed, lineWidth: 1).padding(-3))
        .accessibilityHidden(true)
    }
}

struct PokedexBackground: View {
    @Environment(\.petTheme) private var theme
    var body: some View {
        theme.paper
        .clipShape(PokedexShape())
        .overlay(PokedexShape().stroke(theme.line, lineWidth: 1).padding(0.5))
    }
}

struct PokedexButtonStyle: ButtonStyle {
    @Environment(\.petTheme) private var theme
    var prominent = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        OrbitButtonBody(label: configuration.label, pressed: configuration.isPressed, prominent: prominent, enabled: enabled)
    }
}

private struct OrbitButtonBody: View {
    @Environment(\.petTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: ButtonStyleConfiguration.Label
    let pressed: Bool
    let prominent: Bool
    let enabled: Bool
    @State private var hovering = false
    var body: some View {
        label.font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 10)
            .foregroundStyle(prominent ? .white : theme.ink)
            .background(prominent ? theme.red : hovering ? theme.accentSoft : theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .scaleEffect(reduceMotion || !enabled ? 1 : pressed ? 0.97 : hovering ? 1.025 : 1)
            .opacity(enabled ? 1 : 0.45)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.82), value: hovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: pressed)
    }
}

struct PokedexIconButton: View {
    @Environment(\.petTheme) private var theme
    let symbol: String
    let label: String
    var onRed = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .medium)).frame(width: 32, height: 32)
                .background(onRed ? Color.white.opacity(0.14) : theme.ink.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).foregroundStyle(onRed ? .white : theme.muted)
        .help(label).accessibilityLabel(label)
    }
}

struct PokedexCard<Content: View>: View {
    @Environment(\.petTheme) private var theme
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct PokedexHomeView: View {
    @Environment(\.petTheme) private var theme
    @ObservedObject var model: PetModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                if let url = Bundle.main.url(forResource: model.settings.character.thumbnailResource, withExtension: "png"), let art = NSImage(contentsOf: url) {
                    Image(nsImage: art).resizable().interpolation(.high).scaledToFit().frame(width: 78, height: 78).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("Tu día, en orden.").font(.system(size: 23, weight: .semibold))
                    HStack(spacing: 5) {
                        Circle().fill(model.calendarConnected ? theme.green : theme.gold).frame(width: 6, height: 6)
                        Text(model.calendarConnected ? "Calendario iCal conectado" : "Listo para acompañarte")
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(theme.muted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(theme.paper)

            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Label("Un momento juntos", systemImage: "pawprint.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button("Animaciones") { model.dashboardTab = 4 }
                        .help("Elegir cualquiera de los movimientos")
                }
                HStack(spacing: 8) {
                    Button { model.requestAnimation(.petting) } label: { Label("Dar cariño", systemImage: "heart.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(PokedexButtonStyle(prominent: true))
                    Button { model.requestAnimation(.sit) } label: { Label("Sentarse", systemImage: "pawprint.fill").frame(maxWidth: .infinity) }
                }
                Text("También puedes acariciarlo con ⇧ Mayús + arrastrar.")
                    .font(.system(size: 10)).foregroundStyle(theme.muted)
            }.padding(16).background(theme.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                tile("Agenda", detail: "Próximas reuniones", symbol: "calendar", tab: 0, color: theme.red)
                tile("Tareas", detail: "Tus pendientes del día", symbol: "checklist", tab: 1, color: theme.red)
                tile("Concentración", detail: "Una cosa a la vez", symbol: "timer", tab: 2, color: theme.red)
                tile("Ajustes", detail: "A tu medida", symbol: "slider.horizontal.3", tab: 3, color: theme.blue)
                tile("Notas", detail: "Ideas e historial", symbol: "note.text", tab: 5, color: theme.red)
                tile("Gestos", detail: "\(model.settings.character.clips.count) movimientos", symbol: "pawprint.fill", tab: 4, color: theme.fire)
            }
            HStack(spacing: 8) {
                Image(systemName: model.settings.character.symbol).foregroundStyle(theme.fire)
                Text("FOCO").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(theme.muted)
                Spacer(minLength: 0)
                ForEach([5, 10, 30], id: \.self) { minutes in
                    Button("\(minutes) min") { model.startFocus(minutes: minutes); model.dashboardTab = 2 }
                }
            }.padding(.vertical, 3)
            if let focus = model.settings.focusTimer {
                HStack {
                    Image(systemName: focus.phase == .finished ? "checkmark.circle.fill" : "timer").foregroundStyle(theme.fire)
                    Text(focus.phase == .finished ? "Foco completado · \(focus.durationSeconds / 60) min" : focus.display(at: model.clockNow))
                        .font(.system(size: focus.phase == .finished ? 12 : 22, weight: .semibold)).monospacedDigit()
                    Spacer()
                    if focus.phase != .finished {
                        Button(focus.phase == .paused ? "Reanudar" : "Pausar") { model.pauseOrResumeFocus() }
                    } else {
                        Button("Listo") { model.stopFocus() }
                    }
                }.padding(12).background(theme.gold.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 12))
            } else if let meeting = model.meetings.first(where: { !$0.allDay && $0.end > model.clockNow }) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("PRÓXIMA REUNIÓN · \(ReminderRules.time(meeting.start))").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(theme.red)
                        Text(meeting.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                    }
                    Spacer()
                    if let url = meeting.joinURL {
                        Button { model.openMeeting(url) } label: { Image(systemName: "arrow.up.right") }.help("Entrar a la reunión").accessibilityLabel("Entrar a la reunión")
                    }
                }.padding(12).background(theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1))
            }
        }
    }

    private func tile(_ title: String, detail: String, symbol: String, tab: Int, color: Color) -> some View {
        Button { model.dashboardTab = tab } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(color)
                        .frame(width: 32, height: 30).background(color.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                }
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(theme.muted)
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(theme.ink).background(theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .contentShape(RoundedRectangle(cornerRadius: 13))
        }.buttonStyle(.plain).accessibilityLabel(title)
    }
}

struct PokedexAnimationsView: View {
    @Environment(\.petTheme) private var theme
    @ObservedObject var model: PetModel
    private var clips: [ArcanineClip] { [.petting, .sit] + model.settings.character.clips.filter { $0 != .petting && $0 != .sit } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Los gestos de tu compañero").font(.system(size: 19, weight: .semibold))
            Text("Elige un movimiento para verlo ahora. \(model.settings.character.name) vuelve a descansar al terminar.")
                .font(.system(size: 12)).foregroundStyle(theme.muted)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(clips, id: \.rawValue) { clip in
                    Button { model.requestAnimation(clip) } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Image(systemName: symbol(clip)).font(.system(size: 18)).foregroundStyle(theme.fire)
                                Spacer()
                                Image(systemName: "play.fill").font(.system(size: 10)).foregroundStyle(theme.red)
                            }
                            Text(model.settings.character.title(for: clip)).font(.system(size: 12, weight: .semibold))
                                .lineLimit(2).frame(height: 30, alignment: .topLeading)
                            Text(clip == .idle ? "Reposo continuo" : String(format: "%.1f segundos", clip.duration))
                                .font(.system(size: 10)).foregroundStyle(theme.muted)
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.line, lineWidth: 1))
                            .contentShape(RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).accessibilityLabel("Reproducir: \(model.settings.character.title(for: clip))")
                }
            }
            Text(model.settings.character == .arcanine
                 ? "Sentarse incluye bajar la cadera, descansar sentado y levantarse. Para las caricias también puedes usar ⇧ Mayús + arrastrar sobre Arcanine."
                 : "Mewtwo levita y medita con movimientos tranquilos. Para las caricias también puedes usar ⇧ Mayús + arrastrar sobre él.")
                .font(.system(size: 11)).foregroundStyle(theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func symbol(_ clip: ArcanineClip) -> String {
        switch clip {
        case .petting: return "heart.fill"
        case .sit: return "pawprint.fill"
        case .idle: return "moon.zzz.fill"
        case .curious: return "questionmark.circle"
        case .greeting: return "hand.wave.fill"
        case .happyTail: return "heart.circle"
        case .sniff: return "sparkle.magnifyingglass"
        case .stretch: return "sun.max.fill"
        case .alert: return "bell.fill"
        case .celebration: return "party.popper.fill"
        case .chaseTail: return "arrow.triangle.2.circlepath"
        }
    }
}

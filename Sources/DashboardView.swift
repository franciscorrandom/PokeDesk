import SwiftUI
import ServiceManagement

private let arcanineAccent = ArcanineTheme.red
private let arcanineInk = ArcanineTheme.ink

struct DashboardView: View {
    @ObservedObject var model: PetModel
    var onClose: () -> Void = {}
    @State private var taskTitle = ""
    @State private var taskTime = Date().addingTimeInterval(300)
    @State private var taskDaily = true
    @State private var taskWeekdays = true
    @State private var focusRequest = ""
    @State private var customMinutes = 25

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                PokedexLens()
                VStack(alignment: .leading, spacing: 4) {
                    Text("ARCANINE").font(.system(size: 20, weight: .heavy, design: .rounded)).tracking(1.4)
                    Text(model.dashboardTab == -1 ? "Tu compañero de escritorio" : ["Tu agenda", "Tus tareas", "Tu tiempo de foco", "Tus ajustes", "Tus animaciones", "Tus notas e ideas"][max(0, min(5, model.dashboardTab))])
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.8))
                }
                Spacer()
                if model.speaking { PokedexIconButton(symbol: "speaker.slash", label: "Silenciar voz", onRed: true) { model.voiceSpeaker.stop() } }
                if model.dashboardTab != -1 { PokedexIconButton(symbol: "square.grid.2x2", label: "Menú principal", onRed: true) { model.dashboardTab = -1 } }
                PokedexIconButton(symbol: "xmark", label: "Cerrar menú", onRed: true) { onClose() }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 18)
            .background(LinearGradient(colors: [ArcanineTheme.red, ArcanineTheme.deepRed], startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack(spacing: 4) {
                Circle().fill(ArcanineTheme.red).frame(width: 5, height: 5)
                Circle().fill(ArcanineTheme.gold).frame(width: 5, height: 5)
                Circle().fill(ArcanineTheme.green).frame(width: 5, height: 5)
                Rectangle().fill(ArcanineTheme.line).frame(height: 1).padding(.horizontal, 9)
                PokeballMark().frame(width: 19, height: 19)
            }.padding(.horizontal, 22).padding(.vertical, 10)
            if model.dashboardTab != -1 {
                HStack(spacing: 5) {
                    ForEach(0..<6) { tab in
                        Button { model.dashboardTab = tab } label: {
                            Text(["Agenda", "Tareas", "Foco", "Ajustes", "Gestos", "Notas"][tab])
                                .font(.system(size: 11, weight: .semibold))
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .foregroundStyle(model.dashboardTab == tab ? .white : ArcanineTheme.muted)
                                .background(model.dashboardTab == tab ? arcanineAccent : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                    }
                }.padding(5).background(ArcanineTheme.line.opacity(0.22)).clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 20).padding(.bottom, 16)
            }
            ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = model.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Arcanine necesita tu atención", systemImage: "exclamationmark.circle").foregroundStyle(ArcanineTheme.fire)
                            Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            Button("Entendido") { model.errorMessage = nil }
                        }.padding(12).background(ArcanineTheme.gold.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    if model.dashboardTab == -1 { PokedexHomeView(model: model) }
                    if model.dashboardTab == 0 { agenda }
                    if model.dashboardTab == 1 { tasks }
                    if model.dashboardTab == 2 { concentration }
                    if model.dashboardTab == 3 { preferences }
                    if model.dashboardTab == 4 { PokedexAnimationsView(model: model) }
                    if model.dashboardTab == 5 { PetNotesView(model: model) }
                }.padding(.horizontal, 20).padding(.bottom, 20).frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: model.noteEditorRequest) {
                if model.dashboardTab == 5 { scroll.scrollTo("notes-start", anchor: .top) }
            }
            .onChange(of: model.dashboardTab) {
                if model.dashboardTab == 5 { scroll.scrollTo("notes-start", anchor: .top) }
            }
            }
            Rectangle().fill(ArcanineTheme.line).frame(height: 1).padding(.horizontal, 20)
            HStack {
                Text("ARRASTRA A ARCANINE PARA MOVERLO").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(0.4).foregroundStyle(ArcanineTheme.muted)
                Spacer()
                Button("Probar aviso") { model.testAlert() }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(arcanineAccent)
            }.padding(.horizontal, 20).padding(.vertical, 15)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(arcanineInk)
        .background(PokedexBackground())
        .clipShape(PokedexShape())
        .tint(arcanineAccent)
        .buttonStyle(PokedexButtonStyle())
        .toggleStyle(.switch)
        .controlSize(.small)
        .preferredColorScheme(.light)
        .onAppear { model.refreshCalendar(); model.loginStatus = SMAppService.mainApp.status }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Próximas reuniones").font(.system(size: 19, weight: .semibold, design: .rounded))
                Spacer()
                Button { model.refreshCalendar(force: true) } label: { Image(systemName: "arrow.clockwise") }.help("Actualizar agenda")
            }
            if !model.calendarConnected {
                card {
                    Label("Conecta tu calendario", systemImage: "calendar.badge.clock").font(.headline)
                    Text("Pega el enlace privado iCal en Ajustes. No necesitas una cuenta de Google Cloud ni autorizar Google Tasks.")
                        .font(.system(size: 13)).foregroundStyle(ArcanineTheme.muted)
                    Button("Configurar calendario") { model.dashboardTab = 3 }.buttonStyle(PokedexButtonStyle(prominent: true))
                }
            }
            Text(model.calendarMessage).font(.system(size: 12)).foregroundStyle(ArcanineTheme.muted)
            if model.calendarConnected && model.meetings.isEmpty && !model.calendarBusy {
                card { Label("No hay reuniones próximas en los siguientes 7 días", systemImage: "sun.max") }
            }
            ForEach(Array(model.meetings.prefix(18))) { meeting in
                card {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(meeting.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                            Text(meeting.start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).font(.system(size: 12)).foregroundStyle(ArcanineTheme.muted)
                            Text(meeting.allDay ? "Todo el día" : "\(ReminderRules.time(meeting.start)) – \(ReminderRules.time(meeting.end))")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(arcanineAccent)
                            Text(meeting.calendarName).font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted)
                        }
                        Spacer()
                        if let url = meeting.joinURL { Button("Unirme") { model.openMeeting(url) }.buttonStyle(PokedexButtonStyle()) }
                    }
                }
            }
            if model.meetings.count > 18 { Text("Mostrando las primeras 18 reuniones.").font(.caption).foregroundStyle(ArcanineTheme.muted) }
        }
    }

    private var tasks: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pequeños pendientes, a tiempo").font(.system(size: 19, weight: .semibold, design: .rounded))
            card {
                TextField("Por ejemplo: revisar los pendientes del día", text: $taskTitle).textFieldStyle(.plain).padding(10).background(ArcanineTheme.paper).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(arcanineAccent.opacity(0.18), lineWidth: 1))
                    .onSubmit { addTask() }
                HStack {
                    DatePicker("Avisarme a las", selection: $taskTime, displayedComponents: .hourAndMinute)
                    Spacer()
                }
                Toggle("Repetir cada día", isOn: $taskDaily)
                if taskDaily { Toggle("Solo de lunes a viernes", isOn: $taskWeekdays) }
                Text(taskDaily ? "Las tareas completadas vuelven a estar pendientes al día siguiente que corresponda." : "El aviso es para hoy. Si la hora ya pasó, te avisaré al crearla.")
                    .font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted).fixedSize(horizontal: false, vertical: true)
                Button("Añadir tarea") { addTask() }.buttonStyle(PokedexButtonStyle(prominent: true))
                    .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.settings.tasks.isEmpty {
                Text("Añade tu primera tarea. Puedes usarlo para revisar correos, tomar una pausa o preparar tu jornada.")
                    .font(.system(size: 13)).foregroundStyle(ArcanineTheme.muted)
            }
            ForEach(model.settings.tasks.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }) { task in
                let complete = task.isComplete(at: Date())
                card {
                    HStack(spacing: 12) {
                        Button { model.completeTask(task.id) } label: {
                            Image(systemName: complete ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(complete ? arcanineAccent : .gray)
                        }.buttonStyle(.plain).disabled(complete).help("Marcar como completada")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(task.title).font(.system(size: 13, weight: .medium)).strikethrough(complete).foregroundStyle(complete ? ArcanineTheme.muted : ArcanineTheme.ink)
                            Text(String(format: "%02d:%02d", task.hour, task.minute) + " · " + (task.repeatsDaily ? (task.weekdaysOnly ? "Lunes a viernes" : "Cada día") : "Una vez"))
                                .font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted)
                        }
                        Spacer()
                        Button { model.deleteTask(task.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(ArcanineTheme.muted).help("Eliminar tarea")
                    }
                }
            }
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A tu ritmo").font(.system(size: 19, weight: .semibold, design: .rounded))
            CalendarSettingsView(model: model)
            voicePreferences
            card {
                Picker("Avisar antes de cada reunión", selection: $model.settings.meetingLeadMinutes) {
                    ForEach([1, 5, 10, 15, 30], id: \.self) { Text("\($0) minutos").tag($0) }
                }.onChange(of: model.settings.meetingLeadMinutes) { model.save(); model.tick() }
                Toggle("Sonido al recibir un aviso", isOn: $model.settings.soundEnabled).onChange(of: model.settings.soundEnabled) { model.save() }
                Toggle("Animaciones y reacciones de Arcanine", isOn: $model.settings.motionEnabled).onChange(of: model.settings.motionEnabled) { model.save() }
                Text("Arcanine 3D parpadea, saluda, olfatea, se estira y persigue su cola. Celebra tus tareas y timers; durante el foco se mueve menos. Respeta Reducir movimiento de macOS.").font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted)
                Text("Arrastra para mover · ⌥ Option + arrastra hacia los lados para girar. La orientación elegida se guarda.").font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted)
                Button("Restablecer vista") { model.resetPetView() }
                HStack {
                    Text("Tamaño")
                    Slider(value: $model.settings.petSize, in: 110...230, step: 10).onChange(of: model.settings.petSize) { model.save() }
                }
                Toggle("Abrir Arcanine al iniciar sesión", isOn: Binding(get: { model.loginStatus == .enabled }, set: { _ in model.toggleLogin() }))
                if model.loginStatus == .requiresApproval {
                    Button("Autorizar inicio automático en macOS") { SMAppService.openSystemSettingsLoginItems() }
                }
                Text("Para el inicio automático, coloca Arcanine.app en Aplicaciones y activa esta opción desde esa copia.")
                    .font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted)
                Button(model.settings.pausedUntil.map({ $0 > Date() }) == true ? "Reanudar avisos" : "Pausar avisos durante 1 hora") { model.togglePause() }
            }
            Text("Tus tareas y notas se guardan en este Mac. Los enlaces privados se guardan en el Llavero; la app consulta Google directamente. Los avisos funcionan mientras Arcanine está abierto y el Mac está despierto.")
                .font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func voiceBinding<Value>(_ keyPath: WritableKeyPath<VoicePreferences, Value>) -> Binding<Value> {
        Binding(get: { (model.settings.voice ?? VoicePreferences())[keyPath: keyPath] }, set: { model.setVoice(keyPath, value: $0) })
    }

    var voicePreferences: some View {
        card {
            Label("La voz de Arcanine", systemImage: "waveform").font(.headline)
            Toggle("Avisos hablados", isOn: voiceBinding(\.enabled))
            if model.settings.voice?.enabled != false {
                Text("Avisos de reuniones en inglés").font(.system(size: 12)).foregroundStyle(ArcanineTheme.muted)
                Picker("Voz", selection: Binding(get: { (model.settings.voice ?? VoicePreferences()).selectedEnglishVoice.rawValue }, set: { model.selectEnglishVoice($0) })) {
                    ForEach(EnglishVoice.allCases) { voice in Text(voice.name).tag(voice.rawValue) }
                }
                let voice = (model.settings.voice ?? VoicePreferences()).selectedEnglishVoice
                let missing = model.voiceSpeaker.missingClips(voice: voice)
                let meetingsReady = !missing.contains(.meeting) && !missing.contains(.meetingWithLink)
                if meetingsReady {
                    Label("Avisos de reuniones listos", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(arcanineAccent)
                    Button("Probar aviso de reunión") { model.testVoice(clip: .meeting) }
                        .buttonStyle(PokedexButtonStyle())
                }
                HStack { Text("Volumen"); Slider(value: voiceBinding(\.volume), in: 0...1) }
                Toggle("Avisarme de reuniones con voz", isOn: voiceBinding(\.speakMeetings))
                HStack {
                    Button("Probar voz") { model.testVoice() }.buttonStyle(PokedexButtonStyle(prominent: true))
                    Button("Silenciar ahora") { model.voiceSpeaker.stop() }.disabled(!model.speaking)
                }
                Text("Las voces funcionan sin conexión y anuncian reuniones sin nombres personales. Los timers y las tareas usan un sonido; sus detalles aparecen en pantalla.")
                    .font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var concentration: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Un rato para concentrarte").font(.system(size: 19, weight: .semibold, design: .rounded))
            if let focus = model.settings.focusTimer {
                card {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(focus.phase == .paused ? "En pausa" : (focus.phase == .finished ? "¡Tiempo completado!" : "Tiempo de concentración")).font(.headline)
                            Text(focus.phase == .finished ? "\(focus.durationSeconds / 60) min completados" : focus.display(at: model.clockNow)).font(.system(size: focus.phase == .finished ? 23 : 46, weight: .medium, design: .rounded)).monospacedDigit().foregroundStyle(arcanineAccent)
                        }
                        Spacer()
                        Image(systemName: focus.phase == .finished ? "checkmark.seal" : "timer").font(.system(size: 34)).foregroundStyle(arcanineAccent.opacity(0.7))
                    }
                    ProgressView(value: focus.progress(at: model.clockNow))
                    HStack {
                        if focus.phase != .finished {
                            Button(focus.phase == .paused ? "Reanudar" : "Pausar") { model.pauseOrResumeFocus() }.buttonStyle(PokedexButtonStyle(prominent: true))
                        }
                        Button(focus.phase == .finished ? "Listo" : "Cancelar timer") { model.stopFocus() }
                    }
                }
            }
            card {
                Text("¿Cuánto tiempo necesitas?").font(.headline)
                HStack(spacing: 12) {
                    ForEach([5, 10, 30], id: \.self) { minutes in
                        Button("\(minutes) min") { model.startFocus(minutes: minutes) }.buttonStyle(PokedexButtonStyle(prominent: true))
                    }
                }
                HStack {
                    Stepper("\(customMinutes) minutos", value: $customMinutes, in: 1...180)
                    Spacer()
                    Button("Iniciar") { model.startFocus(minutes: customMinutes) }
                }
                Divider()
                TextField("Pídeme: timer de 5 minutos", text: $focusRequest).textFieldStyle(.plain).padding(10).background(ArcanineTheme.paper).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(arcanineAccent.opacity(0.18), lineWidth: 1))
                    .onSubmit { model.runFocusCommand(focusRequest); focusRequest = "" }
                Button("Pedir a Arcanine") { model.runFocusCommand(focusRequest); focusRequest = "" }
                    .disabled(focusRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("La cuenta regresiva aparece bajo las patas de Arcanine y desaparece al terminar. También puedes iniciar un timer con clic derecho sobre la mascota. El timer continúa al cerrar la app o dormir el Mac; si lo pausas, el tiempo restante se conserva.")
                .font(.system(size: 12)).foregroundStyle(ArcanineTheme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func addTask() {
        model.addTask(title: taskTitle, date: taskTime, daily: taskDaily, weekdays: taskWeekdays)
        taskTitle = ""
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        PokedexCard(content: content)
    }
}

struct AlertBubbleView: View {
    @ObservedObject var model: PetModel
    var body: some View {
        if let alert = model.currentAlert {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    PokeballMark().frame(width: 22, height: 22)
                    Label(alert.focusTimerID != nil ? "TU TIEMPO" : ((alert.taskID != nil) ? "TU TAREA" : "ARCANINE TE AVISA"), systemImage: alert.focusTimerID != nil ? "timer" : ((alert.taskID != nil) ? "checklist" : "calendar"))
                        .font(.system(size: 9, weight: .bold, design: .rounded)).tracking(0.5).foregroundStyle(.white)
                    Spacer()
                    if model.speaking { PokedexIconButton(symbol: "speaker.slash", label: "Silenciar voz", onRed: true) { model.voiceSpeaker.stop() } }
                    PokedexIconButton(symbol: "xmark", label: "Cerrar aviso", onRed: true) { model.dismissAlert() }
                }.padding(10).background(ArcanineTheme.red).clipShape(RoundedRectangle(cornerRadius: 12))
                Text(alert.title).font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(2)
                Text(alert.message).font(.system(size: 12)).foregroundStyle(ArcanineTheme.muted).lineLimit(2)
                if let url = alert.joinURL, alert.meetingID != nil {
                    Button { model.openMeeting(url) } label: {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "link")
                            Text(url.absoluteString).font(.system(size: 10, design: .monospaced)).lineLimit(2).truncationMode(.middle)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).foregroundStyle(arcanineAccent).help(url.absoluteString)
                } else if alert.meetingID != nil {
                    Text("Esta reunión no incluye un enlace de videollamada.").font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted)
                }
                Spacer(minLength: 0)
                HStack(spacing: 8) {
                    if let id = alert.taskID {
                        Button("Hecho") { model.completeTask(id) }.buttonStyle(PokedexButtonStyle(prominent: true))
                    } else if let url = alert.joinURL {
                        Button("Entrar a la reunión") { model.openMeeting(url); model.dismissAlert() }.buttonStyle(PokedexButtonStyle(prominent: true))
                    } else {
                        Button("Entendido") { model.dismissAlert() }.buttonStyle(PokedexButtonStyle(prominent: true))
                    }
                    Button("En 5 min") { model.snoozeAlert() }.buttonStyle(PokedexButtonStyle())
                }.controlSize(.small)
            }
            .padding(18).frame(width: 350, height: 320, alignment: .topLeading)
            .background(PokedexBackground()).clipShape(PokedexShape())
            .foregroundStyle(arcanineInk).tint(arcanineAccent).preferredColorScheme(.light)
        }
    }
}

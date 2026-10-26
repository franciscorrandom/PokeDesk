import SwiftUI
import ServiceManagement


struct DashboardView: View {
    private var theme: PetTheme { PetTheme(character: model.settings.character) }
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
                PokeballMark().frame(width: 27, height: 27).padding(5)
                    .background(theme.accentSoft).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("PokéDesk").font(.system(size: 17, weight: .semibold))
                Spacer()
                if model.speaking { PokedexIconButton(symbol: "speaker.slash", label: "Silenciar voz") { model.voiceSpeaker.stop() } }
                if model.dashboardTab != -1 { PokedexIconButton(symbol: "house", label: "Inicio") { model.dashboardTab = -1 } }
                PokedexIconButton(symbol: "slider.horizontal.3", label: "Ajustes") { model.dashboardTab = 3 }
                PokedexIconButton(symbol: "xmark", label: "Cerrar menú") { onClose() }
            }
            .padding(.horizontal, 21).padding(.vertical, 16)
            Rectangle().fill(theme.line).frame(height: 1)
            OrbitCompanionBar(model: model)
                HStack(spacing: 3) {
                    ForEach([0, 1, 2, 5, 4], id: \.self) { tab in
                        Button { model.dashboardTab = tab } label: {
                            Label(["Agenda", "Tareas", "Foco", "Ajustes", "Gestos", "Notas"][tab], systemImage: ["calendar", "checkmark.circle", "timer", "slider.horizontal.3", "sparkles", "note.text"][tab])
                                .font(.system(size: 11, weight: .medium))
                                .frame(maxWidth: .infinity).padding(.vertical, 9)
                                .foregroundStyle(model.dashboardTab == tab ? theme.red : theme.muted)
                                .background(model.dashboardTab == tab ? theme.paper : .clear)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(color: theme.ink.opacity(model.dashboardTab == tab ? 0.06 : 0), radius: 3, y: 1)
                        }.buttonStyle(.plain)
                    }
                }.padding(4).background(theme.card).clipShape(RoundedRectangle(cornerRadius: 13))
                    .padding(.horizontal, 20).padding(.bottom, 16)
            ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = model.errorMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("\(model.settings.character.name) necesita tu atención", systemImage: "exclamationmark.circle").foregroundStyle(theme.fire)
                            Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            Button("Entendido") { model.errorMessage = nil }
                        }.padding(12).background(theme.gold.opacity(0.2)).clipShape(RoundedRectangle(cornerRadius: 10))
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
            Rectangle().fill(theme.line).frame(height: 1).padding(.horizontal, 20)
            HStack {
                Label(model.calendarConnected ? "Calendario conectado" : "Tu compañero está aquí", systemImage: model.calendarConnected ? "calendar.badge.checkmark" : "pawprint")
                    .font(.system(size: 11)).foregroundStyle(theme.muted)
                Spacer()
                Button("Probar aviso") { model.testAlert() }.buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.red)
            }.padding(.horizontal, 20).padding(.vertical, 13)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(theme.ink)
        .background(PokedexBackground()).environment(\.petTheme, theme)
        .clipShape(PokedexShape())
        .tint(theme.red)
        .buttonStyle(PokedexButtonStyle())
        .toggleStyle(.switch)
        .controlSize(.small)
        .preferredColorScheme(.light)
        .onAppear { model.refreshCalendar(); model.loginStatus = SMAppService.mainApp.status }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Próximas reuniones").font(.system(size: 19, weight: .semibold))
                Spacer()
                Button { model.refreshCalendar(force: true) } label: { Image(systemName: "arrow.clockwise") }.help("Actualizar agenda")
            }
            if !model.calendarConnected {
                card {
                    Label("Conecta tu calendario", systemImage: "calendar.badge.clock").font(.headline)
                    Text("Pega el enlace privado iCal en Ajustes. No necesitas una cuenta de Google Cloud ni autorizar Google Tasks.")
                        .font(.system(size: 13)).foregroundStyle(theme.muted)
                    Button("Configurar calendario") { model.dashboardTab = 3 }.buttonStyle(PokedexButtonStyle(prominent: true))
                }
            }
            Text(model.calendarMessage).font(.system(size: 12)).foregroundStyle(theme.muted)
            if model.calendarConnected && model.meetings.isEmpty && !model.calendarBusy {
                card { Label("No hay reuniones próximas en los siguientes 7 días", systemImage: "sun.max") }
            }
            ForEach(Array(model.meetings.prefix(18))) { meeting in
                card {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(meeting.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                            Text(meeting.start, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).font(.system(size: 12)).foregroundStyle(theme.muted)
                            Text(meeting.allDay ? "Todo el día" : "\(ReminderRules.time(meeting.start)) – \(ReminderRules.time(meeting.end))")
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(theme.red)
                            Text(meeting.calendarName).font(.system(size: 11)).foregroundStyle(theme.muted)
                        }
                        Spacer()
                        if let url = meeting.joinURL { Button("Unirme") { model.openMeeting(url) }.buttonStyle(PokedexButtonStyle()) }
                    }
                }
            }
            if model.meetings.count > 18 { Text("Mostrando las primeras 18 reuniones.").font(.caption).foregroundStyle(theme.muted) }
        }
    }

    private var tasks: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pequeños pendientes, a tiempo").font(.system(size: 19, weight: .semibold))
            card {
                TextField("Por ejemplo: revisar los pendientes del día", text: $taskTitle).textFieldStyle(.plain).padding(10).background(theme.paper).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.red.opacity(0.18), lineWidth: 1))
                    .onSubmit { addTask() }
                HStack {
                    DatePicker("Avisarme a las", selection: $taskTime, displayedComponents: .hourAndMinute)
                    Spacer()
                }
                Toggle("Repetir cada día", isOn: $taskDaily)
                if taskDaily { Toggle("Solo de lunes a viernes", isOn: $taskWeekdays) }
                Text(taskDaily ? "Las tareas completadas vuelven a estar pendientes al día siguiente que corresponda." : "El aviso es para hoy. Si la hora ya pasó, te avisaré al crearla.")
                    .font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
                Button("Añadir tarea") { addTask() }.buttonStyle(PokedexButtonStyle(prominent: true))
                    .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if model.settings.tasks.isEmpty {
                Text("Añade tu primera tarea. Puedes usarlo para revisar correos, tomar una pausa o preparar tu jornada.")
                    .font(.system(size: 13)).foregroundStyle(theme.muted)
            }
            ForEach(model.settings.tasks.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }) { task in
                let complete = task.isComplete(at: Date())
                card {
                    HStack(spacing: 12) {
                        Button { model.completeTask(task.id) } label: {
                            Image(systemName: complete ? "checkmark.circle.fill" : "circle").font(.system(size: 22)).foregroundStyle(complete ? theme.red : .gray)
                        }.buttonStyle(.plain).disabled(complete).help("Marcar como completada")
                        VStack(alignment: .leading, spacing: 5) {
                            Text(task.title).font(.system(size: 13, weight: .medium)).strikethrough(complete).foregroundStyle(complete ? theme.muted : theme.ink)
                            Text(String(format: "%02d:%02d", task.hour, task.minute) + " · " + (task.repeatsDaily ? (task.weekdaysOnly ? "Lunes a viernes" : "Cada día") : "Una vez"))
                                .font(.system(size: 11)).foregroundStyle(theme.muted)
                        }
                        Spacer()
                        Button { model.deleteTask(task.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(theme.muted).help("Eliminar tarea")
                    }
                }
            }
        }
    }

    private var preferences: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("A tu ritmo").font(.system(size: 19, weight: .semibold))
            characterPreferences
            CalendarSettingsView(model: model)
            voicePreferences
            card {
                Picker("Avisar antes de cada reunión", selection: $model.settings.meetingLeadMinutes) {
                    ForEach([1, 5, 10, 15, 30], id: \.self) { Text("\($0) minutos").tag($0) }
                }.onChange(of: model.settings.meetingLeadMinutes) { model.save(); model.tick() }
                Toggle("Sonido al recibir un aviso", isOn: $model.settings.soundEnabled).onChange(of: model.settings.soundEnabled) { model.save() }
                Toggle("Animaciones y reacciones de \(model.settings.character.name)", isOn: $model.settings.motionEnabled).onChange(of: model.settings.motionEnabled) { model.save() }
                Toggle("Giro suave en reposo", isOn: Binding(get: { model.settings.ambientRotationEnabled ?? true }, set: { model.settings.ambientRotationEnabled = $0; model.save() }))
                Text("Gira muy lentamente de lado a lado, unos 25° por lado en un ciclo de ocho minutos. Se pausa durante el foco, los avisos y la interacción. Puedes seguir girándolo con Option y arrastrar.").font(.system(size: 11)).foregroundStyle(theme.muted)
                Text("\(model.settings.character.description) Celebra tus tareas y timers; durante el foco se mueve menos. Respeta Reducir movimiento de macOS.").font(.system(size: 11)).foregroundStyle(theme.muted)
                Text("Arrastra para mover · ⌥ Option + arrastra hacia los lados para girar. La orientación elegida se guarda.").font(.system(size: 11)).foregroundStyle(theme.muted)
                Button("Repetir salida de la Pokébola") { model.requestPokeball() }
                Button("Restablecer vista") { model.resetPetView() }
                HStack {
                    Text("Tamaño")
                    Slider(value: $model.settings.petSize, in: 110...230, step: 10).onChange(of: model.settings.petSize) { model.save() }
                }
                Toggle("Abrir PokéDesk al iniciar sesión", isOn: Binding(get: { model.loginStatus == .enabled }, set: { _ in model.toggleLogin() }))
                if model.loginStatus == .requiresApproval {
                    Button("Autorizar inicio automático en macOS") { SMAppService.openSystemSettingsLoginItems() }
                }
                Text("Para el inicio automático, coloca PokeDesk.app en Aplicaciones y activa esta opción desde esa copia.")
                    .font(.system(size: 11)).foregroundStyle(theme.muted)
                Button(model.settings.pausedUntil.map({ $0 > Date() }) == true ? "Reanudar avisos" : "Pausar avisos durante 1 hora") { model.togglePause() }
            }
            Text("Tus tareas y notas se guardan en este Mac. Los enlaces privados se guardan en el Llavero; la app consulta Google directamente. Los avisos funcionan mientras PokéDesk está abierto y el Mac está despierto.")
                .font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var characterPreferences: some View {
        card {
            Label("Tu compañero", systemImage: "person.crop.circle.badge.checkmark").font(.headline)
            PetCharacterChooser(selected: model.settings.character) { model.selectCharacter($0) }
            Text("El cambio conserva tu agenda, tareas, notas y timer. Cada compañero recuerda su orientación.")
                .font(.system(size: 11)).foregroundStyle(theme.muted)
        }
    }

    private func voiceBinding<Value>(_ keyPath: WritableKeyPath<VoicePreferences, Value>) -> Binding<Value> {
        Binding(get: { (model.settings.voice ?? VoicePreferences())[keyPath: keyPath] }, set: { model.setVoice(keyPath, value: $0) })
    }

    var voicePreferences: some View {
        card {
            Label("La voz de \(model.settings.character.name)", systemImage: "waveform").font(.headline)
            Toggle("Avisos hablados", isOn: voiceBinding(\.enabled))
            if model.settings.voice?.enabled != false {
                Text("Avisos de reuniones en inglés").font(.system(size: 12)).foregroundStyle(theme.muted)
                Picker("Voz", selection: Binding(get: { (model.settings.voice ?? VoicePreferences()).selectedEnglishVoice.rawValue }, set: { model.selectEnglishVoice($0) })) {
                    ForEach(EnglishVoice.allCases) { voice in Text(voice.name).tag(voice.rawValue) }
                }
                let voice = (model.settings.voice ?? VoicePreferences()).selectedEnglishVoice
                let missing = model.voiceSpeaker.missingClips(voice: voice)
                let meetingsReady = !missing.contains(.meeting) && !missing.contains(.meetingWithLink)
                if meetingsReady {
                    Label("Avisos de reuniones listos", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 11)).foregroundStyle(theme.red)
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
                    .font(.system(size: 11)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var concentration: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Un rato para concentrarte").font(.system(size: 19, weight: .semibold))
            if let focus = model.settings.focusTimer {
                card {
                    HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(focus.phase == .paused ? "En pausa" : (focus.phase == .finished ? "¡Tiempo completado!" : "Tiempo de concentración")).font(.headline)
                            Text(focus.phase == .finished ? "\(focus.durationSeconds / 60) min completados" : focus.display(at: model.clockNow)).font(.system(size: focus.phase == .finished ? 23 : 46, weight: .medium)).monospacedDigit().foregroundStyle(theme.red)
                        }
                        Spacer()
                        Image(systemName: focus.phase == .finished ? "checkmark.seal" : "timer").font(.system(size: 34)).foregroundStyle(theme.red.opacity(0.7))
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
                TextField("Pídeme: timer de 5 minutos", text: $focusRequest).textFieldStyle(.plain).padding(10).background(theme.paper).clipShape(RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(theme.red.opacity(0.18), lineWidth: 1))
                    .onSubmit { model.runFocusCommand(focusRequest); focusRequest = "" }
                Button("Pedir a \(model.settings.character.name)") { model.runFocusCommand(focusRequest); focusRequest = "" }
                    .disabled(focusRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("La cuenta regresiva aparece bajo tu compañero y desaparece al terminar. También puedes iniciar un timer con clic derecho sobre la mascota. El timer continúa al cerrar la app o dormir el Mac; si lo pausas, el tiempo restante se conserva.")
                .font(.system(size: 12)).foregroundStyle(theme.muted).fixedSize(horizontal: false, vertical: true)
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
    private var theme: PetTheme { PetTheme(character: model.settings.character) }
    @ObservedObject var model: PetModel
    var body: some View {
        if let alert = model.currentAlert {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    PokeballMark().frame(width: 22, height: 22)
                    Label(alert.focusTimerID != nil ? "TU TIEMPO" : ((alert.taskID != nil) ? "TU TAREA" : "POKÉDESK TE AVISA"), systemImage: alert.focusTimerID != nil ? "timer" : ((alert.taskID != nil) ? "checklist" : "calendar"))
                        .font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(.white)
                    Spacer()
                    if model.speaking { PokedexIconButton(symbol: "speaker.slash", label: "Silenciar voz", onRed: true) { model.voiceSpeaker.stop() } }
                    PokedexIconButton(symbol: "xmark", label: "Cerrar aviso", onRed: true) { model.dismissAlert() }
                }.padding(10).background(theme.red).clipShape(RoundedRectangle(cornerRadius: 12))
                Text(alert.title).font(.system(size: 17, weight: .semibold)).lineLimit(2)
                Text(alert.message).font(.system(size: 12)).foregroundStyle(theme.muted).lineLimit(2)
                if let url = alert.joinURL, alert.meetingID != nil {
                    Button { model.openMeeting(url) } label: {
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: "link")
                            Text(url.absoluteString).font(.system(size: 10, design: .monospaced)).lineLimit(2).truncationMode(.middle)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain).foregroundStyle(theme.red).help(url.absoluteString)
                } else if alert.meetingID != nil {
                    Text("Esta reunión no incluye un enlace de videollamada.").font(.system(size: 11)).foregroundStyle(theme.muted)
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
            .background(PokedexBackground()).environment(\.petTheme, theme).clipShape(PokedexShape())
            .foregroundStyle(theme.ink).tint(theme.red).preferredColorScheme(.light).environment(\.petTheme, theme)
        }
    }
}

import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "America/Santiago")!
func date(_ year: Int = 2026, _ month: Int = 9, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}
var count = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
    count += 1
}

let wednesday = date(2026, 9, 30, 9)
var task = DailyTask(title: "Revisar pendientes", hour: 10, minute: 0, createdAt: wednesday)
check(!task.shouldRemind(at: wednesday, calendar: calendar), "No avisar antes de la hora")
check(task.shouldRemind(at: date(2026, 9, 30, 10), calendar: calendar), "Avisar al vencer")
task.lastRemindedOn = "2026-09-30"
check(!task.shouldRemind(at: date(2026, 9, 30, 11), calendar: calendar), "No duplicar el aviso de hoy")
check(task.shouldRemind(at: date(2026, 10, 1, 11), calendar: calendar), "Reactivar al día siguiente")
task.completedOn = "2026-09-30"
check(task.isComplete(at: date(2026, 9, 30, 11), calendar: calendar), "Completar hoy")
check(!task.isComplete(at: date(2026, 10, 1, 11), calendar: calendar), "Reiniciar tarea diaria mañana")
check(!task.shouldRemind(at: date(2026, 10, 3, 11), calendar: calendar), "Excluir sábado")
check(!task.shouldRemind(at: date(2026, 10, 4, 11), calendar: calendar), "Excluir domingo")
task.weekdaysOnly = false
check(task.shouldRemind(at: date(2026, 10, 3, 11), calendar: calendar), "Permitir fin de semana si se elige")
var once = DailyTask(title: "Enviar documento", hour: 10, minute: 0, repeatsDaily: false, createdAt: wednesday)
check(once.shouldRemind(at: date(2026, 10, 1, 11), calendar: calendar), "Recuperar una tarea única vencida al abrir app")
once.lastRemindedOn = "once"
check(!once.shouldRemind(at: date(2026, 10, 2, 11), calendar: calendar), "Tarea única no se repite mañana")
once.completedAt = date(2026, 9, 30, 11)
check(once.isComplete(at: date(2026, 10, 2, 11), calendar: calendar), "Conservar finalización de tarea única")

var meeting = Meeting(id: "trabajo", title: "Equipo", start: date(2026, 9, 30, 12), end: date(2026, 9, 30, 13), calendarName: "Trabajo", allDay: false)
check(!ReminderRules.shouldRemind(meeting, now: date(2026, 9, 30, 11, 49), leadMinutes: 10, fired: [:]), "No avisar antes del margen")
check(ReminderRules.shouldRemind(meeting, now: date(2026, 9, 30, 11, 50), leadMinutes: 10, fired: [:]), "Avisar 10 minutos antes")
let fired = [ReminderRules.meetingKey(meeting, leadMinutes: 10): wednesday]
check(!ReminderRules.shouldRemind(meeting, now: date(2026, 9, 30, 11, 55), leadMinutes: 10, fired: fired), "No repetir reunión ya avisada")
check(!ReminderRules.shouldRemind(meeting, now: date(2026, 9, 30, 12, 5), leadMinutes: 10, fired: [:]), "No avisar reuniones antiguas al despertar")
meeting.allDay = true
check(!ReminderRules.shouldRemind(meeting, now: date(2026, 9, 30, 11, 55), leadMinutes: 10, fired: [:]), "No alertar eventos de todo el día")
meeting.allDay = false
meeting.start = date(2026, 10, 1, 12)
meeting.end = date(2026, 10, 1, 13)
check(ReminderRules.shouldRemind(meeting, now: date(2026, 10, 1, 11, 50), leadMinutes: 10, fired: fired), "Avisar siguiente ocurrencia recurrente")
check(ReminderRules.joinURL(in: ["Reunión: https://meet.google.com/abc-defg-hij"])?.host == "meet.google.com", "Extraer Google Meet")
check(ReminderRules.joinURL(in: ["https://meet.google.com.evil.test/abc"]) == nil, "Rechazar host que imita Meet")
check(ReminderRules.joinURL(in: ["file:///tmp/documento"]) == nil, "No abrir rutas locales desde notas")

var settings = PetSettings()
settings.tasks = [task, once]
settings.snoozed = [PetAlert(title: "Pendiente", message: "Recordar después", taskID: task.id, dueAt: date(2026, 10, 1, 12))]
let recovered = try JSONDecoder().decode(PetSettings.self, from: JSONEncoder().encode(settings))
check(recovered.tasks == settings.tasks && recovered.snoozed.first?.taskID == task.id, "Conservar tareas y avisos pospuestos entre reinicios")
settings.petYaw = .pi / 2
let savedOrientation = try JSONDecoder().decode(PetSettings.self, from: JSONEncoder().encode(settings))
check(savedOrientation.petYaw == .pi / 2 && savedOrientation.tasks == settings.tasks, "Conservar orientación 3D sin perder tareas")
var focus = FocusTimer(minutes: 5, now: wednesday)
check(focus.display(at: wednesday) == "05:00", "Mostrar cinco minutos en la cara")
check(focus.display(at: wednesday.addingTimeInterval(61)) == "03:59", "Actualizar cuenta regresiva real")
focus.pause(at: wednesday.addingTimeInterval(61))
check(focus.remaining(at: wednesday.addingTimeInterval(3600)) == 239, "La pausa conserva el tiempo")
focus.resume(at: wednesday.addingTimeInterval(3600))
check(focus.remaining(at: wednesday.addingTimeInterval(3601)) == 238, "Reanudar desde el tiempo pausado")
check(focus.remaining(at: wednesday.addingTimeInterval(7200)) == 0, "Terminar aunque el Mac duerma")
check(focus.progress(at: wednesday.addingTimeInterval(7200)) == 1, "No exceder progreso completo")
check(FocusCommand.minutes(in: "Miga, timer de 10 minutos") == 10, "Entender petición de timer")
check(FocusCommand.minutes(in: "timer de treinta minutos") == 30, "Entender números escritos")
check(FocusCommand.minutes(in: "5") == 5, "Permitir solo un número en el campo de concentración")
check(FocusCommand.minutes(in: "0 minutos") == nil, "Rechazar duración cero")
check(FocusCommand.minutes(in: "999 minutos") == nil, "Rechazar duración fuera de rango")
check(FocusCommand.minutes(in: "5.5 minutos") == nil, "No interpretar un decimal como otra duración")
let pausedData = try JSONEncoder().encode(focus)
let persistedFocus = try JSONDecoder().decode(FocusTimer.self, from: pausedData)
check(persistedFocus == focus, "Conservar timer entre reinicios")
var oldObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
oldObject.removeValue(forKey: "focusTimer")
oldObject.removeValue(forKey: "calendarFeeds")
oldObject.removeValue(forKey: "petYaw")
let migrated = try JSONDecoder().decode(PetSettings.self, from: JSONSerialization.data(withJSONObject: oldObject))
check(migrated.tasks == settings.tasks && migrated.focusTimer == nil && migrated.calendarFeeds == nil, "Migrar ajustes de la primera versión sin perder tareas")
check(migrated.petYaw == nil, "Datos anteriores mantienen el ángulo original sin añadir una configuración obligatoria")

let faceStart = Date(timeIntervalSince1970: 1_000_000)
var faceFocus = FocusTimer(minutes: 5, now: faceStart)
check(faceFocus.showsOnFace(at: faceStart), "Mostrar timer activo en la cara")
check(!faceFocus.showsOnFace(at: faceStart.addingTimeInterval(300)), "Recuperar cara en el instante de llegar a cero")
faceFocus.pause(at: faceStart.addingTimeInterval(60))
check(faceFocus.showsOnFace(at: faceStart.addingTimeInterval(900)), "Mantener timer pausado en la cara")
faceFocus.phase = .finished
check(!faceFocus.showsOnFace(at: faceStart), "Un timer terminado guardado no deja 00:00 al reiniciar")
check(migrated.voice == nil, "Añadir voz sin perder datos de versiones anteriores")
check(migrated.notes == nil && migrated.tasks == settings.tasks, "Añadir notas sin perder datos de versiones anteriores")
var voice = VoicePreferences()
check(voice.selectedEnglishVoice == .holden, "Datos anteriores usan Holden en inglés")
check(EnglishVoice.allCases.count == 2, "Ofrecer únicamente Gracie y Holden")
voice.englishVoice = "gracie"
check(voice.selectedEnglishVoice == .gracie, "Seleccionar Gracie")
let savedVoice = try JSONDecoder().decode(VoicePreferences.self, from: JSONEncoder().encode(voice))
check(savedVoice.selectedEnglishVoice == .gracie, "Conservar voz elegida entre reinicios")
voice.englishVoice = "voz-desconocida"
check(voice.selectedEnglishVoice == .holden, "No activar voces de otros idiomas")
var legacyVoice = try JSONSerialization.jsonObject(with: JSONEncoder().encode(voice)) as! [String: Any]
legacyVoice.removeValue(forKey: "englishVoice")
legacyVoice["voiceID"] = "com.apple.voice.compact.es-MX.Paulina"
let migratedVoice = try JSONDecoder().decode(VoicePreferences.self, from: JSONSerialization.data(withJSONObject: legacyVoice))
check(migratedVoice.selectedEnglishVoice == .holden && migratedVoice.speakMeetings, "Migrar voz antigua sin perder categorías ni leer español")
check(VoiceClip.focusStart(minutes: 5) == .focus5, "Avisar cinco minutos con duración")
check(VoiceClip.focusStart(minutes: 10) == .focus10, "Avisar diez minutos con duración")
check(VoiceClip.focusStart(minutes: 30) == .focus30, "Avisar treinta minutos con duración")
check(VoiceClip.focusStart(minutes: 25) == .focusOther, "Otro timer usa aviso genérico sin decir una duración incorrecta")
check(!VoiceClip.focus5.phrase.contains("Francisco"), "Avisos sin nombre personal del creador")
let spokenMeeting = PetAlert(title: "Equipo", message: "Empieza en 5 min", meetingID: "m", joinURL: URL(string: "https://meet.google.com/abc-defg-hij"), dueAt: faceStart)
check(VoiceClip.reminder(spokenMeeting, preferences: voice) == .meetingWithLink, "Avisar que hay enlace en pantalla")
var meetingWithoutLink = spokenMeeting
meetingWithoutLink.joinURL = nil
check(VoiceClip.reminder(meetingWithoutLink, preferences: voice) == .meeting, "No prometer enlace si la reunión no lo incluye")
let spokenTask = PetAlert(title: "Pendiente", message: "Hoy", taskID: UUID(), dueAt: faceStart)
check(VoiceClip.reminder(spokenTask, preferences: voice) == .task, "Avisar tarea local")
let localSpokenTask = PetAlert(title: "Tarea", message: "Hoy", taskID: UUID(), dueAt: faceStart)
check(VoiceClip.reminder(localSpokenTask, preferences: voice) == .task, "Avisar tareas locales")
let completedFocusAlert = PetAlert(title: "Foco", message: "Terminado", dueAt: faceStart, focusTimerID: UUID())
check(VoiceClip.reminder(completedFocusAlert, preferences: voice) == .focusFinished, "Avisar finalización de foco")
voice.speakTimers = false
check(VoiceClip.reminder(completedFocusAlert, preferences: voice) == nil, "Respetar silenciamiento de timers")
voice.speakTasks = false
check(VoiceClip.reminder(localSpokenTask, preferences: voice) == nil, "Respetar silenciamiento de tareas")
voice.speakMeetings = false
check(VoiceClip.reminder(spokenMeeting, preferences: voice) == nil, "Respetar silenciamiento de reuniones")
voice.speakMeetings = true
voice.enabled = false
check(VoiceClip.reminder(spokenMeeting, preferences: voice) == nil, "Respetar silenciamiento general")
print("\(count) comprobaciones correctas de timers, cara, voz, migración, recurrencia y recordatorios.")

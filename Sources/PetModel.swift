import AppKit
import SwiftUI
import ServiceManagement

@MainActor final class PetModel: ObservableObject {
    @Published var settings: PetSettings
    @Published var meetings: [Meeting] = []
    @Published var calendarConnected = false
    @Published var calendarMessage = "Conecta Google Calendar para ver tus reuniones."
    @Published var errorMessage: String?
    @Published var currentAlert: PetAlert?
    @Published var loginStatus = SMAppService.mainApp.status
    @Published var clockNow = Date()
    @Published var dashboardTab = 0
    @Published var noteFeedback: String?
    @Published var noteEditorRequest = 0
    // One shared draft survives switching between the quick card and full panel.
    @Published var noteDraft = NoteDraft() { didSet { noteFeedback = nil } }
    @Published var speaking = false
    lazy var voiceSpeaker: MigaVoice = {
        let speaker = MigaVoice()
        speaker.onSpeakingChanged = { [weak self] in self?.speaking = $0 }
        speaker.onError = { [weak self] message in self?.errorMessage = message }
        return speaker
    }()
    @Published var calendarBusy = false
    @Published var calendarLastUpdated: Date?
    lazy var calendarService = CalendarService(vault: isTestStorage ? CalendarMemoryVault() : CalendarKeychain())
    var calendarSyncTask: Task<Void, Never>?
    var calendarGeneration = 0
    var nextCalendarFetch = Date.distantPast
    var calendarFailures = 0
    var feedMeetings: [UUID: [Meeting]] = [:]
    var isTestStorage = false
    private var clockTimer: Timer?
    var onTaskCompleted: (() -> Void)?
    var onFocusStarted: (() -> Void)?
    var onAnimationRequested: ((ArcanineClip) -> Void)?
    var onAlert: ((PetAlert) -> Void)?
    var onSettingsChanged: (() -> Void)?
    private let storageURL: URL
    private var alertQueue: [PetAlert] = []
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var storageReadable = true

    init(storageURL: URL? = nil) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.storageURL = storageURL ?? base.appendingPathComponent("Arcanine-iCal/estado.json")
        isTestStorage = storageURL != nil
        if let data = try? Data(contentsOf: self.storageURL) {
            do { settings = try JSONDecoder().decode(PetSettings.self, from: data) }
            catch {
                settings = PetSettings()
                storageReadable = false
                errorMessage = "No pude leer tus datos guardados. El archivo original se conserva; revisa estado.json antes de guardar cambios."
            }
        } else { settings = PetSettings() }
    }

    func requestAnimation(_ clip: ArcanineClip) {
        guard settings.motionEnabled else {
            errorMessage = "Activa los movimientos en Ajustes para reproducir las animaciones de Arcanine."
            return
        }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            errorMessage = "macOS tiene activado Reducir movimiento. Puedes cambiarlo en Ajustes del Sistema → Accesibilidad → Pantalla."
            return
        }
        onAnimationRequested?(clip)
    }

    func start() {
        refreshCalendar()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.async { self?.refreshCalendar(force: true); self?.tick() }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in DispatchQueue.main.async { self?.tick() } }
        RunLoop.main.add(timer!, forMode: .common)
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.clockNow = Date(); self?.checkFocusTimer() }
        }
        RunLoop.main.add(clockTimer!, forMode: .common)
        tick()
    }

    @discardableResult func save() -> Bool {
        guard storageReadable else {
            errorMessage = "El archivo estado.json no se puede leer. No se sobrescribirá; tus cambios de esta sesión no se guardarán hasta recuperar el archivo."
            onSettingsChanged?()
            return false
        }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: storageURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
        } catch {
            errorMessage = "No pude guardar tus cambios: \(error.localizedDescription)"
            onSettingsChanged?()
            return false
        }
        onSettingsChanged?()
        return true
    }

    var notes: [PetNote] { settings.notes ?? [] }
    var noteCategories: [String] { NoteRules.categories(in: notes) }
    var editingNote: PetNote? { notes.first { $0.id == noteDraft.id } }
    var noteHasChanges: Bool {
        guard let note = editingNote else { return noteDraft.canSave }
        return noteDraft.title.trimmingCharacters(in: .whitespacesAndNewlines) != note.title ||
            noteDraft.body != note.body || NoteRules.category(noteDraft.category).map(NoteRules.key) != note.category.map(NoteRules.key)
    }

    func newNote() { noteDraft = NoteDraft(); noteEditorRequest += 1 }
    func editNote(_ id: UUID) {
        guard let note = notes.first(where: { $0.id == id }), note.archivedAt == nil else { return }
        noteDraft = NoteDraft(id: note.id, title: note.title, body: note.body, category: note.category ?? "")
        noteEditorRequest += 1
    }

    @discardableResult func saveNote(now: Date = Date()) -> Bool {
        guard noteDraft.canSave else { noteFeedback = "Escribe algo antes de guardar la nota."; return false }
        let previous = settings.notes
        var updated = notes
        let title = noteDraft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let requested = NoteRules.category(noteDraft.category)
        let category = requested.flatMap { value in noteCategories.first { NoteRules.key($0) == NoteRules.key(value) } ?? value }
        let id: UUID
        if let editingID = noteDraft.id {
            guard let index = updated.firstIndex(where: { $0.id == editingID }), updated[index].archivedAt == nil else {
                noteFeedback = "Esta nota está archivada. Recupérala desde el historial para editarla."
                return false
            }
            let old = updated[index]
            guard old.title != title || old.body != noteDraft.body || old.category != category else {
                noteFeedback = "La nota ya está guardada."; return true
            }
            updated[index].revisions.append(NoteRevision(title: old.title, body: old.body, category: old.category, savedAt: old.updatedAt))
            updated[index].title = title; updated[index].body = noteDraft.body; updated[index].category = category
            updated[index].updatedAt = now
            id = editingID
        } else {
            let note = PetNote(title: title, body: noteDraft.body, category: category, createdAt: now, updatedAt: now)
            updated.append(note); id = note.id
        }
        settings.notes = updated
        guard save() else {
            settings.notes = previous
            noteFeedback = "No se pudo guardar. Tu texto sigue en el editor; vuelve a intentarlo."
            return false
        }
        editNote(id)
        noteFeedback = "Guardada en tu Mac"
        return true
    }

    @discardableResult func setNoteArchived(_ id: UUID, archived: Bool, now: Date = Date()) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        let previous = settings.notes
        settings.notes?[index].archivedAt = archived ? now : nil
        guard save() else {
            settings.notes = previous
            noteFeedback = "No se pudo guardar el cambio. Vuelve a intentarlo."
            return false
        }
        if archived && noteDraft.id == id { newNote() }
        noteFeedback = archived ? "Nota archivada · puedes recuperarla del historial" : "Nota recuperada"
        return true
    }

    func resetPetView() { settings.petYaw = nil; save() }

    func addTask(title: String, date: Date, daily: Bool, weekdays: Bool) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        settings.tasks.append(DailyTask(title: String(title.prefix(180)), hour: components.hour ?? 9, minute: components.minute ?? 0, repeatsDaily: daily, weekdaysOnly: weekdays))
        save()
        tick()
    }

    func completeTask(_ id: UUID) {
        guard let index = settings.tasks.firstIndex(where: { $0.id == id }) else { return }
        guard !settings.tasks[index].isComplete(at: Date()) else { return }
        settings.tasks[index].completedOn = ReminderRules.dayKey(Date())
        settings.tasks[index].completedAt = Date()
        settings.snoozed.removeAll { $0.taskID == id }
        alertQueue.removeAll { $0.taskID == id }
        if currentAlert?.taskID == id { dismissAlert() }
        save()
        onTaskCompleted?()
    }

    func deleteTask(_ id: UUID) {
        settings.tasks.removeAll { $0.id == id }
        settings.snoozed.removeAll { $0.taskID == id }
        alertQueue.removeAll { $0.taskID == id }
        if currentAlert?.taskID == id { dismissAlert() }
        save()
    }

    func removeObsoleteMeetingAlerts() {
        let ids = Set(meetings.filter { $0.end > Date() }.map(\.id))
        alertQueue.removeAll { $0.meetingID.map { !ids.contains($0) } ?? false }
        settings.snoozed.removeAll { $0.meetingID.map { !ids.contains($0) } ?? false }
        if let id = currentAlert?.meetingID, !ids.contains(id) { dismissAlert() }
    }

    func tick() {
        let now = Date()
        checkFocusTimer()
        if now >= nextCalendarFetch { refreshCalendar() }
        guard settings.pausedUntil.map({ $0 > now }) != true else { return }
        var changed = false
        for index in settings.tasks.indices where settings.tasks[index].shouldRemind(at: now) {
            let task = settings.tasks[index]
            enqueue(PetAlert(title: task.title, message: task.repeatsDaily ? "Tu recordatorio de hoy" : "Tienes una tarea pendiente", taskID: task.id, dueAt: now))
            settings.tasks[index].lastRemindedOn = task.repeatsDaily ? ReminderRules.dayKey(now) : "once"
            changed = true
        }
        for meeting in meetings where ReminderRules.shouldRemind(meeting, now: now, leadMinutes: settings.meetingLeadMinutes, fired: settings.firedMeetings) {
            enqueue(PetAlert(title: meeting.title, message: ReminderRules.meetingMessage(meeting, now: now), meetingID: meeting.id, joinURL: meeting.joinURL, dueAt: now))
            settings.firedMeetings[ReminderRules.meetingKey(meeting, leadMinutes: settings.meetingLeadMinutes)] = now
            changed = true
        }
        let ready = settings.snoozed.filter { $0.dueAt <= now }
        settings.snoozed.removeAll { $0.dueAt <= now }
        for alert in ready {
            if let meetingID = alert.meetingID, !meetings.contains(where: { $0.id == meetingID && $0.end > now }) { continue }
            if let taskID = alert.taskID, !settings.tasks.contains(where: { $0.id == taskID && !$0.isComplete(at: now) }) { continue }
            if let timerID = alert.focusTimerID, settings.focusTimer?.id != timerID { continue }
            enqueue(alert)
        }
        if !ready.isEmpty { changed = true }
        let oldCount = settings.firedMeetings.count
        settings.firedMeetings = settings.firedMeetings.filter { $0.value > now.addingTimeInterval(-14 * 86400) }
        if oldCount != settings.firedMeetings.count { changed = true }
        if changed { save() }
        presentNextAlert()
    }

    func enqueue(_ alert: PetAlert) {
        guard !alertQueue.contains(where: { $0.id == alert.id }), currentAlert?.id != alert.id else { return }
        alertQueue.append(alert)
    }

    private func presentNextAlert() {
        guard currentAlert == nil, !alertQueue.isEmpty else { return }
        let alert = alertQueue.removeFirst()
        currentAlert = alert
        onAlert?(alert)
        let preferences = settings.voice ?? VoicePreferences()
        if let phrase = VoiceClip.reminder(alert, preferences: preferences), !isTestStorage,
           voiceSpeaker.audioURL(phrase, voice: preferences.selectedEnglishVoice) != nil {
            voiceSpeaker.speak(phrase, preferences: preferences)
        } else if settings.soundEnabled { NSSound(named: "Glass")?.play() }
    }

    func dismissAlert() {
        if !isTestStorage { voiceSpeaker.stop() }
        currentAlert = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.presentNextAlert() }
    }

    func snoozeAlert() {
        guard var alert = currentAlert else { return }
        alert.dueAt = Date().addingTimeInterval(5 * 60)
        settings.snoozed.append(alert)
        save()
        dismissAlert()
    }

    func testAlert() {
        if let meeting = meetings.first(where: { !$0.allDay && $0.joinURL != nil && $0.end > Date() }) {
            enqueue(PetAlert(title: meeting.title, message: "Vista previa del aviso · \(ReminderRules.time(meeting.start))", meetingID: meeting.id, joinURL: meeting.joinURL, dueAt: Date()))
        } else {
            enqueue(PetAlert(title: "¡Hola! Soy Arcanine", message: "Así te avisaré. Cuando una reunión incluya un enlace, podrás entrar desde aquí.", dueAt: Date()))
        }
        presentNextAlert()
    }

    func togglePause() {
        settings.pausedUntil = settings.pausedUntil.map({ $0 > Date() }) == true ? nil : Date().addingTimeInterval(3600)
        save()
        if settings.pausedUntil == nil { tick() }
    }

    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            loginStatus = SMAppService.mainApp.status
            if loginStatus == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            errorMessage = "No pude cambiar el inicio automático. Copia Arcanine.app a Aplicaciones y vuelve a intentarlo. \(error.localizedDescription)"
        }
    }

    func openCalendarHelp() { NSWorkspace.shared.open(URL(string: "https://support.google.com/calendar/answer/37648?hl=es")!) }
    func openMeeting(_ url: URL) {
        guard url.scheme?.lowercased() == "https" else { return }
        NSWorkspace.shared.open(url)
    }


    func startFocus(minutes: Int) {
        guard (1...180).contains(minutes) else { return }
        alertQueue.removeAll { $0.focusTimerID != nil }
        settings.snoozed.removeAll { $0.focusTimerID != nil }
        if currentAlert?.focusTimerID != nil { dismissAlert() }
        clockNow = Date()
        settings.focusTimer = FocusTimer(minutes: minutes, now: clockNow)
        save()
        onFocusStarted?()
        if settings.soundEnabled, !isTestStorage { NSSound(named: "Glass")?.play() }
    }

    func pauseOrResumeFocus() {
        guard var focus = settings.focusTimer else { return }
        let now = Date()
        if focus.phase == .paused { focus.resume(at: now) }
        else { focus.pause(at: now) }
        settings.focusTimer = focus
        clockNow = now
        save()
        checkFocusTimer()
    }

    func stopFocus() {
        settings.focusTimer = nil
        settings.snoozed.removeAll { $0.focusTimerID != nil }
        alertQueue.removeAll { $0.focusTimerID != nil }
        if currentAlert?.focusTimerID != nil { dismissAlert() }
        save()
    }

    func runFocusCommand(_ command: String) {
        let command = command.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es_CL"))
        if let minutes = FocusCommand.minutes(in: command) { startFocus(minutes: minutes); return }
        if command.contains("cancel") || command.contains("deten") { stopFocus(); return }
        if command.contains("pausa") && settings.focusTimer?.phase == .running { pauseOrResumeFocus(); return }
        if (command.contains("continua") || command.contains("reanuda")) && settings.focusTimer?.phase == .paused { pauseOrResumeFocus(); return }
        errorMessage = "Puedes pedirme «timer de 5 minutos», «pausa» o «reanuda». Elige entre 1 y 180 minutos."
    }

    func checkFocusTimer() {
        guard var focus = settings.focusTimer, focus.phase == .running, focus.remaining(at: Date()) == 0 else { return }
        focus.phase = .finished
        if !focus.notified {
            focus.notified = true
            enqueue(PetAlert(title: "Terminó tu concentración", message: "Completaste \(focus.durationSeconds / 60) minutos. Es un buen momento para una pausa.", dueAt: Date(), focusTimerID: focus.id))
        }
        settings.focusTimer = focus
        save()
        presentNextAlert()
    }

    func setVoice<Value>(_ keyPath: WritableKeyPath<VoicePreferences, Value>, value: Value) {
        if settings.voice == nil { settings.voice = VoicePreferences() }
        settings.voice?[keyPath: keyPath] = value
        if settings.voice?.enabled == false { voiceSpeaker.stop() }
        save()
    }

    func testVoice(clip: VoiceClip = .preview) {
        let preferences = settings.voice ?? VoicePreferences()
        voiceSpeaker.speak(clip, preferences: preferences)
    }

    func selectEnglishVoice(_ value: String) {
        guard EnglishVoice(rawValue: value) != nil else { return }
        voiceSpeaker.stop()
        setVoice(\.englishVoice, value: value)
    }
}

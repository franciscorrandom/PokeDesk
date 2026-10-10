import AppKit

extension PetModel {
    var feeds: [CalendarFeed] { settings.calendarFeeds ?? [] }
    func refreshCalendar(force: Bool = false) {
        guard !isTestStorage, !calendarBusy, force || Date() >= nextCalendarFetch else { return }
        guard !feeds.isEmpty else {
            meetings = []; calendarConnected = false
            calendarMessage = "Pega tu enlace privado iCal en Ajustes para ver reuniones y recibir avisos."
            nextCalendarFetch = .distantFuture; return
        }
        calendarBusy = true
        let generation = calendarGeneration, chosen = feeds
        calendarSyncTask = Task { @MainActor in
            var failures: [String] = [], updated = feeds
            for feed in chosen {
                do {
                    let value = try await calendarService.fetch(feed)
                    guard !Task.isCancelled, generation == calendarGeneration else { return }
                    feedMeetings[feed.id] = value.meetings
                    if let i = updated.firstIndex(where: { $0.id == feed.id }) { updated[i].lastUpdated = Date() }
                } catch is CancellationError { return }
                catch {
                    guard generation == calendarGeneration else { return }
                    failures.append(error.localizedDescription)
                }
            }
            guard generation == calendarGeneration else { return }
            meetings = chosen.flatMap { feedMeetings[$0.id] ?? [] }.filter { $0.end > Date() }.sorted { $0.start < $1.start }
            calendarConnected = chosen.contains { feedMeetings[$0.id] != nil }
            settings.calendarFeeds = updated; calendarBusy = false
            if failures.isEmpty {
                calendarFailures = 0; calendarLastUpdated = Date()
                calendarMessage = "Calendario actualizado · \(meetings.count) reuniones en los siguientes 7 días."
            } else {
                calendarFailures += 1
                calendarMessage = failures.first! + (meetings.isEmpty ? "" : " Se muestra la última agenda recibida.")
            }
            nextCalendarFetch = Date().addingTimeInterval(min(3600, 300 * pow(2, Double(min(calendarFailures, 3)))))
            removeObsoleteMeetingAlerts(); save(); tick()
        }
    }
    func subscribeCalendar(_ address: String, name: String, replacing: UUID? = nil) {
        guard !calendarBusy, save() else { return }
        calendarBusy = true; calendarGeneration += 1
        let generation = calendarGeneration, id = replacing ?? UUID()
        calendarMessage = "Comprobando el enlace y leyendo las próximas reuniones…"
        calendarSyncTask = Task { @MainActor in
            do {
                let result = try await calendarService.connect(address, id: id, name: name)
                guard !Task.isCancelled, generation == calendarGeneration else { return }
                var next = feeds
                let feed = CalendarFeed(id: id, name: result.name, lastUpdated: Date())
                if let i = next.firstIndex(where: { $0.id == id }) { next[i] = feed } else { next.append(feed) }
                settings.calendarFeeds = next; feedMeetings[id] = result.meetings
                meetings = next.flatMap { feedMeetings[$0.id] ?? [] }.sorted { $0.start < $1.start }
                calendarConnected = true; calendarBusy = false; calendarFailures = 0; calendarLastUpdated = Date()
                nextCalendarFetch = Date().addingTimeInterval(300)
                calendarMessage = "\(result.name) conectado · \(result.meetings.count) reuniones. Los cambios se consultan cada cinco minutos."
                removeObsoleteMeetingAlerts()
                if !save() { calendarMessage = "El calendario se leyó, pero no pude guardar su configuración. Revisa el error de almacenamiento antes de cerrar la app." }
                tick()
            } catch is CancellationError { calendarBusy = false }
            catch {
                calendarBusy = false; calendarMessage = error.localizedDescription
            }
        }
    }
    func cancelCalendarConnection() {
        calendarGeneration += 1; calendarSyncTask?.cancel(); calendarBusy = false
        nextCalendarFetch = Date().addingTimeInterval(300)
        calendarMessage = "Consulta cancelada. Puedes volver a intentarlo cuando quieras."
    }
    func removeCalendar(_ id: UUID) {
        guard !calendarBusy, save() else { return }
        calendarBusy = true; calendarGeneration += 1
        Task { @MainActor in
            defer { calendarBusy = false }
            do {
                try await calendarService.remove(id)
                settings.calendarFeeds = feeds.filter { $0.id != id }; feedMeetings[id] = nil
                meetings = feeds.flatMap { feedMeetings[$0.id] ?? [] }.sorted { $0.start < $1.start }
                calendarConnected = !feeds.isEmpty; removeObsoleteMeetingAlerts()
                calendarMessage = feeds.isEmpty ? "Calendario desconectado. Tus tareas, notas y timers siguen disponibles." : "Calendario eliminado."
                nextCalendarFetch = feeds.isEmpty ? .distantFuture : Date().addingTimeInterval(300); save()
            } catch { calendarMessage = error.localizedDescription }
        }
    }
}


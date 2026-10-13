import Foundation

private var checks = 0
private func check(_ condition: Bool, _ message: String) {
    precondition(condition, message); checks += 1
}
private func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private func ics(_ events: String, zone: String = "UTC", extra: String = "") -> String {
    "BEGIN:VCALENDAR\nVERSION:2.0\nPRODID:-//Arcanine Tests//ES\nX-WR-CALNAME:Trabajo de ejemplo\nX-WR-TIMEZONE:\(zone)\n\(extra)\(events)\nEND:VCALENDAR\n".replacingOccurrences(of: "\n", with: "\r\n")
}
private func event(_ uid: String, start: String = "20261009T150000Z", extra: String = "") -> String {
    "BEGIN:VEVENT\nUID:\(uid)\nDTSTART:\(start)\nDURATION:PT1H\nSUMMARY:Reunión \(uid)\n\(extra)END:VEVENT"
}

private final class CalendarHTTP: URLProtocol {
    static var answers: [(Int, String, [String:String])] = []
    static var requests: [URLRequest] = []
    static var nextData: Data?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let next = Self.answers.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: next.0, httpVersion: "HTTP/1.1", headerFields: next.2)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let payload = Self.nextData ?? Data(next.1.utf8); Self.nextData = nil
        client?.urlProtocol(self, didLoad: payload); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class FailingVault: CalendarVault {
    func read(_ id: UUID) throws -> String? { "https://calendar.google.com/calendar/ical/example/private-test/basic.ics" }
    func write(_ value: String, id: UUID) throws { throw CalendarIssue.message("No se pudo guardar") }
    func delete(_ id: UUID) throws {}
}
private final class SlowVault: CalendarVault {
    func read(_ id: UUID) throws -> String? {
        Thread.sleep(forTimeInterval: 0.2)
        return "https://calendar.google.com/calendar/ical/example/private-test/basic.ics"
    }
    func write(_ value: String, id: UUID) throws {}
    func delete(_ id: UUID) throws {}
}

@main struct CalendarTests {
    @MainActor static func main() async throws {
        let parser = CalendarParser(directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Assets/Calendar"))
        let now = instant("2026-10-09T00:00:00Z"), id = UUID()
        let address = "https://calendar.google.com/calendar/ical/example/private-test/basic.ics"
        check(try CalendarAddress.validate(address).scheme == "https", "Aceptar dirección iCal de Google")
        check(try CalendarAddress.validate(address.replacingOccurrences(of: "https://", with: "webcal://")).scheme == "https", "Normalizar webcal a HTTPS")
        for bad in ["http://calendar.google.com/calendar/ical/a/basic.ics", "https://calendar.google.com.evil.test/calendar/ical/a/basic.ics", "https://example.com/calendar/ical/a/basic.ics", "file:///tmp/a.ics", "https://user@calendar.google.com/calendar/ical/a/basic.ics", "https://calendar.google.com:443/calendar/ical/a/basic.ics", "https://calendar.google.com/calendar/u/0/r"] {
            check((try? CalendarAddress.validate(bad)) == nil, "Rechazar enlace no permitido")
        }
        let single = ics(event("simple", extra: "DESCRIPTION:Entrar en https://meet.google.com/abc-defg-hij\n"))
        let result = try parser.parse(single, now: now, feedID: id)
        check(result.name == "Trabajo de ejemplo" && result.meetings.count == 1, "Leer nombre y reunión")
        check(result.meetings[0].start == instant("2026-10-09T15:00:00Z") && result.meetings[0].end == instant("2026-10-09T16:00:00Z"), "Leer fecha y duración UTC")
        check(result.meetings[0].joinURL?.host == "meet.google.com", "Ofrecer link de reunión")
        check(try parser.parse(single, now: now, feedID: UUID()).meetings[0].id != result.meetings[0].id, "Identidad independiente para cada calendario")
        check(try parser.parse(single, now: now, feedID: id, name: "Equipo").name == "Equipo", "Nombre elegido por usuario")
        check((try? parser.parse("<html>error</html>", now: now, feedID: id)) == nil, "Rechazar HTML sin calendario")
        let daily = event("daily", extra: "RRULE:FREQ=DAILY;COUNT=12\nEXDATE:20261010T150000Z\nRDATE:20261009T180000Z\n")
        let cancelled = "BEGIN:VEVENT\nUID:daily\nRECURRENCE-ID:20261011T150000Z\nSTATUS:CANCELLED\nEND:VEVENT"
        let moved = event("daily", start: "20261012T180000Z", extra: "RECURRENCE-ID:20261012T150000Z\n")
        let other = event("other", extra: "RRULE:FREQ=DAILY;COUNT=2\n")
        let repeated = try parser.parse(ics(daily + "\n" + cancelled + "\n" + moved + "\n" + other), now: now, feedID: id)
        let occurrences = repeated.meetings.filter { $0.id.contains("/daily#") }
        check(occurrences.count == 6, "Expandir siete días con EXDATE, RDATE y cancelación")
        check(!occurrences.contains { $0.start == instant("2026-10-10T15:00:00Z") || $0.start == instant("2026-10-11T15:00:00Z") }, "No mostrar ocurrencias excluidas o canceladas")
        check(occurrences.filter { $0.start == instant("2026-10-12T18:00:00Z") }.count == 1, "Mover ocurrencia sin duplicarla")
        check(repeated.meetings.filter { $0.id.contains("/other#") }.map(\.start) == [instant("2026-10-09T15:00:00Z"),instant("2026-10-10T15:00:00Z")], "Una excepción no modifica otra serie con UID distinto")
        let cancelledSeries = try parser.parse(ics(daily + "\nBEGIN:VEVENT\nUID:daily\nSTATUS:CANCELLED\nEND:VEVENT\n" + moved), now: now, feedID: id)
        check(cancelledSeries.meetings.isEmpty, "Cancelar serie completa incluidas sus excepciones")
        let movedIn = event("far", start: "20261012T180000Z", extra: "RECURRENCE-ID:20261212T150000Z\n")
        check(try parser.parse(ics(movedIn), now: now, feedID: id).meetings.count == 1, "Incluir excepción movida desde fuera de la ventana")
        let local = "BEGIN:VEVENT\nUID:chile\nDTSTART;TZID=America/Santiago:20261009T090000\nDTEND;TZID=America/Santiago:20261009T100000\nSUMMARY:Equipo\nEND:VEVENT"
        check(try parser.parse(ics(local), now: now, feedID: id).meetings[0].start == instant("2026-10-09T12:00:00Z"), "TZID IANA sin VTIMEZONE usa la zona horaria nativa")
        let dst = "BEGIN:VEVENT\nUID:dst\nDTSTART;TZID=America/New_York:20261031T090000\nDTEND;TZID=America/New_York:20261031T100000\nRRULE:FREQ=DAILY;COUNT=3\nSUMMARY:Cambio de hora\nEND:VEVENT"
        check(try parser.parse(ics(dst), now: instant("2026-10-31T00:00:00Z"), feedID: id).meetings.map(\.start) == [instant("2026-10-31T13:00:00Z"),instant("2026-11-01T14:00:00Z"),instant("2026-11-02T14:00:00Z")], "Recurrencia respeta cambio de horario de verano")
        let allDay = "BEGIN:VEVENT\nUID:day\nDTSTART;VALUE=DATE:20261009\nDTEND;VALUE=DATE:20261010\nSUMMARY:Día libre\nEND:VEVENT"
        check(try parser.parse(ics(allDay, zone: "America/Santiago"), now: now, feedID: id).meetings[0].allDay, "Reconocer eventos de todo el día")
        let definition = "BEGIN:VTIMEZONE\nTZID:Custom/Office\nBEGIN:STANDARD\nDTSTART:19700101T000000\nTZOFFSETFROM:+0200\nTZOFFSETTO:+0200\nEND:STANDARD\nEND:VTIMEZONE\n"
        let custom = local.replacingOccurrences(of: "America/Santiago", with: "Custom/Office")
        check(try parser.parse(ics(custom, extra: definition), now: now, feedID: id).meetings[0].start == instant("2026-10-09T07:00:00Z"), "Leer definición VTIMEZONE incluida en el feed")
        check((try? parser.parse(ics(local.replacingOccurrences(of: "America/Santiago", with: "Unknown/Invalid")), now: now, feedID: id)) == nil, "Zona desconocida produce error sin inventar horarios")
        let folded = "BEGIN:VEVENT\nUID:folded\nDTSTART:20261009T150000Z\nDTEND:20261009T160000Z\nSUMMARY:Revisión de\n  equipo\nDESCRIPTION:Primera línea\\nhttps://meet.google.com/abc-defg-hij\nEND:VEVENT"
        let unfolding = try parser.parse(ics(folded), now: now, feedID: id)
        check(unfolding.meetings[0].title == "Revisión de equipo" && unfolding.meetings[0].joinURL != nil, "Desplegar líneas y escapes iCal")

        let big = ics(event("large"), extra: "X-ARCHIVE-NOTE:" + String(repeating: "x", count: 11 * 1024 * 1024) + "\n")
        check(try parser.parse(big, now: now, feedID: id).meetings.count == 1, "Leer un calendario de trabajo mayor al antiguo límite de 10 MB")
        check(try CalendarPayload.decode(Data([0xef,0xbb,0xbf]) + Data(single.utf8)) == single, "Aceptar UTF-8 con BOM")
        check(try CalendarPayload.decode(single.data(using: .utf16)!) == single, "Aceptar un calendario UTF-16 identificado por BOM")
        let splitCharacter = Data("BEGIN:VCALENDAR\r\nSUMMARY:Caf".utf8) + Data([0xc3,13,10,32,0xa9]) + Data("\r\nEND:VCALENDAR\r\n".utf8)
        check(try CalendarPayload.decode(splitCharacter).contains("Café"), "Desplegar una línea que divide un carácter UTF-8")
        do { _ = try CalendarPayload.decode(Data([0xff,0x80])); preconditionFailure("Texto binario aceptado") }
        catch { check(error.localizedDescription.contains("codificación"), "Distinguir codificación de tamaño") }
        do { _ = try CalendarPayload.decode(Data("<html>Google Workspace</html>".utf8)); preconditionFailure("HTML aceptado") }
        catch { check(error.localizedDescription.contains("organización"), "Explicar cuando se recibe una página de acceso") }

        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CalendarHTTP.self]
        let vault = CalendarMemoryVault(), service = CalendarService(vault: vault, parser: parser, session: URLSession(configuration: config))
        CalendarHTTP.answers = [(200, ics(daily), ["ETag":"test-v1"]),(304,"",[:]),(403,"",[:])]
        let connected = try await service.connect(address, id: id, name: "Equipo", now: now)
        check(vault.links[id] == address && connected.meetings.count == 7, "Validar y guardar enlace solo después de leerlo")
        let fresh = try await service.fetch(CalendarFeed(id: id, name: "Equipo"), now: now.addingTimeInterval(86400))
        check(CalendarHTTP.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "test-v1", "Usar ETag para actualizaciones")
        check(fresh.meetings.allSatisfy { $0.end > now.addingTimeInterval(86400) } && fresh.meetings.contains { $0.start == instant("2026-10-16T15:00:00Z") }, "304 expande nueva ventana y elimina reuniones vencidas")
        do { _ = try await service.fetch(CalendarFeed(id: id, name: "Equipo"), now: now); preconditionFailure("403 aceptado") }
        catch { check(!error.localizedDescription.contains(address) && vault.links[id] == address, "Error no revela enlace ni borra conexión") }
        try await service.remove(id); check(vault.links[id] == nil, "Desconectar elimina enlace guardado")
        CalendarHTTP.answers = [(200,big,[:])]
        var largeResponsive = false
        let largeHeartbeat = Task { @MainActor in try await Task.sleep(nanoseconds: 30_000_000); largeResponsive = true }
        let largeSnapshot = try await service.connect(address, id: id, name: "Equipo grande", now: now)
        check(largeSnapshot.meetings.count == 1 && largeResponsive, "Descargar y leer 11 MB sin bloquear el hilo de la mascota")
        _ = try await largeHeartbeat.value
        CalendarHTTP.answers = [(200,single,["Content-Length":String(CalendarPayload.maximumBytes + 1)])]
        do { _ = try await service.fetch(CalendarFeed(id: id, name: "Equipo"), now: now); preconditionFailure("Límite de cabecera ignorado") }
        catch { check(error.localizedDescription.contains("50 MB") && vault.links[id] == address, "Limitar una descarga excesiva sin borrar la conexión") }
        CalendarHTTP.answers = [(304,"",[:])]
        check(try await service.fetch(CalendarFeed(id: id, name: "Equipo"), now: now).meetings.count == 1, "Una descarga rechazada conserva la caché y el ETag anteriores")
        let failing = CalendarService(vault: FailingVault(), parser: parser, session: URLSession(configuration: config))
        CalendarHTTP.answers = [(200,single,["ETag":"failed"]),(200,single,[:])]
        do { _ = try await failing.connect(address, id: id, name: "Equipo", now: now); preconditionFailure("Llavero fallido aceptado") }
        catch { check(true, "Propagar error al guardar") }
        _ = try await failing.fetch(CalendarFeed(id: id, name: "Equipo"), now: now)
        check(CalendarHTTP.requests.last?.value(forHTTPHeaderField: "If-None-Match") == nil, "Fallo al guardar no deja validadores de otro enlace")
        let slow = CalendarService(vault: SlowVault(), parser: parser, session: URLSession(configuration: config))
        CalendarHTTP.answers = [(200,single,[:])]
        var responsive = false
        let heartbeat = Task { @MainActor in try await Task.sleep(nanoseconds: 30_000_000); responsive = true }
        _ = try await slow.fetch(CalendarFeed(id: id, name: "Equipo"), now: now)
        check(responsive, "La lectura lenta no bloquea el hilo de la mascota")
        _ = try await heartbeat.value
        print("\(checks) comprobaciones iCal correctas: fechas, repeticiones, cancelaciones, DST, privacidad y actualización HTTP.")
    }
}

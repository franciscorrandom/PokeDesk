import Foundation
import JavaScriptCore

enum CalendarIssue: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
}

struct CalendarSnapshot {
    var name: String
    var meetings: [Meeting]
}

/// Each parse creates an isolated JS context and runs on the service's worker queue.
final class CalendarParser {
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? Bundle.main.resourceURL!.appendingPathComponent("Calendar")
    }
    static func timestamp(_ json: String, timezone: String) -> Double {
        guard let data = json.data(using: .utf8), let parts = try? JSONDecoder().decode(DateParts.self, from: data),
              let zone = TimeZone(identifier: timezone) else { return .nan }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day,
            hour: parts.hour, minute: parts.minute, second: parts.second))?.timeIntervalSince1970 ?? .nan
    }
    func parse(_ text: String, now: Date, feedID: UUID, name: String = "") throws -> CalendarSnapshot {
        guard text.utf8.count <= 10 * 1024 * 1024, text.contains("BEGIN:VCALENDAR") else {
            throw CalendarIssue.message("El enlace no entregó un calendario iCal válido. Copia la dirección secreta en formato iCal de Google Calendar.")
        }
        guard let context = JSContext() else { throw CalendarIssue.message("No pude iniciar el lector de calendarios.") }
        var failed = false
        context.exceptionHandler = { _, _ in failed = true } // Never expose secret URLs or calendar contents in errors/logs.
        let convert: @convention(block) (String, String) -> Double = { json, timezone in Self.timestamp(json, timezone: timezone) }
        context.setObject(convert, forKeyedSubscript: "nativeTimestamp" as NSString)
        for file in ["ical.js", "reader.js"] { context.evaluateScript(try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)) }
        guard !failed else { throw CalendarIssue.message("No pude cargar el lector iCal incluido en la app.") }
        let end = now.addingTimeInterval(7 * 86400)
        guard let json = context.objectForKeyedSubscript("readCalendar")?.call(withArguments: [text, now.timeIntervalSince1970,
            end.timeIntervalSince1970, TimeZone.current.identifier])?.toString(), !failed,
              let data = json.data(using: .utf8), let parsed = try? JSONDecoder().decode(Parsed.self, from: data) else {
            throw CalendarIssue.message("No pude interpretar las fechas o repeticiones del calendario. Comprueba que el enlace sea iCal y que sus zonas horarias sean válidas.")
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? String(parsed.name.prefix(100)) : String(name.prefix(100))
        return CalendarSnapshot(name: title, meetings: parsed.events.map {
            Meeting(id: "\(feedID.uuidString)/\($0.id)", title: String($0.title.prefix(300)), start: Date(timeIntervalSince1970: $0.start),
                end: Date(timeIntervalSince1970: $0.end), calendarName: title, joinURL: ReminderRules.joinURL(in: [$0.links]), allDay: $0.allDay)
        })
    }
    private struct DateParts: Decodable { var year, month, day, hour, minute, second: Int }
    private struct Parsed: Decodable { var name: String; var events: [Event] }
    private struct Event: Decodable { var id, title, calendarName, links: String; var start, end: Double; var allDay: Bool }
}

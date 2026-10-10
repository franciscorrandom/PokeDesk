import Foundation
import Security
import LocalAuthentication

enum CalendarAddress {
    static func validate(_ value: String) throws -> URL {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("webcal://") { text = "https://" + text.dropFirst(9) }
        guard text.count <= 4096, let url = URL(string: text), url.scheme == "https",
              ["calendar.google.com", "www.google.com"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.port == nil, url.fragment == nil,
              url.path.hasPrefix("/calendar/ical/"), url.path.hasSuffix(".ics") else {
            throw CalendarIssue.message("Pega la dirección secreta en formato iCal de Google Calendar. Debe ser un enlace HTTPS que termine en .ics; no sirve el enlace para compartir o insertar el calendario.")
        }
        return url
    }
}

protocol CalendarVault {
    func read(_ id: UUID) throws -> String?
    func write(_ value: String, id: UUID) throws
    func delete(_ id: UUID) throws
}

struct CalendarKeychain: CalendarVault {
    private func query(_ id: UUID) -> [String: Any] {
        let context = LAContext(); context.interactionNotAllowed = true
        return [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "io.github.franciscorrandom.arcanine.ical.links",
         kSecAttrAccount as String: id.uuidString, kSecUseAuthenticationContext as String: context]
    }
    func read(_ id: UUID) throws -> String? {
        var q = query(id); q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let result = SecItemCopyMatching(q as CFDictionary, &item)
        if result == errSecItemNotFound { return nil }
        guard result == errSecSuccess, let data = item as? Data, let text = String(data: data, encoding: .utf8) else {
            throw CalendarIssue.message("El Llavero no permitió recuperar este enlace. Puedes volver a pegarlo para recuperar la conexión.")
        }
        return text
    }
    func write(_ value: String, id: UUID) throws {
        let q = query(id), data = Data(value.utf8)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var create = q; create[kSecValueData as String] = data; create[kSecAttrLabel as String] = "Arcanine · calendario privado"
            create[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(create as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw CalendarIssue.message("No pude guardar el enlace en el Llavero. La conexión anterior se conserva.") }
    }
    func delete(_ id: UUID) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw CalendarIssue.message("El Llavero no permitió eliminar el enlace guardado.") }
    }
}

final class CalendarMemoryVault: CalendarVault {
    var links: [UUID: String] = [:]
    func read(_ id: UUID) throws -> String? { links[id] }
    func write(_ value: String, id: UUID) throws { links[id] = value }
    func delete(_ id: UUID) throws { links.removeValue(forKey: id) }
}

private final class CalendarRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.flatMap { try? CalendarAddress.validate($0.absoluteString) } == nil ? nil : request)
    }
}

@MainActor final class CalendarService {
    private let vault: CalendarVault
    private let queue = DispatchQueue(label: "arcanine.calendar.worker", qos: .utility)
    private let parser: CalendarParser
    private let session: URLSession
    private var validators: [UUID: (String?, String?)] = [:]
    init(vault: CalendarVault = CalendarKeychain(), parser: CalendarParser = CalendarParser(), session: URLSession? = nil) {
        self.vault = vault; self.parser = parser
        let config = URLSessionConfiguration.ephemeral; config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 45
        config.httpShouldSetCookies = false; config.urlCache = nil
        self.session = session ?? URLSession(configuration: config, delegate: CalendarRedirects(), delegateQueue: nil)
    }
    private func work<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in queue.async {
            do { continuation.resume(returning: try operation()) } catch { continuation.resume(throwing: error) }
        } }
    }
    func connect(_ value: String, id: UUID, name: String, now: Date = Date()) async throws -> CalendarSnapshot {
        let url = try CalendarAddress.validate(value)
        let snapshot = try await download(url, id: id, name: name, now: now, conditional: false)
        try Task.checkCancellation()
        let vault = self.vault
        do { try await work { try vault.write(url.absoluteString, id: id) } }
        catch { validators[id] = nil; rawCalendars[id] = nil; throw error }
        return snapshot
    }
    func fetch(_ feed: CalendarFeed, now: Date = Date()) async throws -> CalendarSnapshot {
        let vault = self.vault
        guard let text = try await work({ try vault.read(feed.id) }) else {
            throw CalendarIssue.message("Este calendario necesita su enlace iCal. Pégalo de nuevo en Ajustes.")
        }
        return try await download(CalendarAddress.validate(text), id: feed.id, name: feed.name, now: now, conditional: true)
    }
    func remove(_ id: UUID) async throws {
        let vault = self.vault; try await work { try vault.delete(id) }; validators[id] = nil; rawCalendars[id] = nil
    }
    private func download(_ url: URL, id: UUID, name: String, now: Date, conditional: Bool) async throws -> CalendarSnapshot {
        var request = URLRequest(url: url); request.setValue("text/calendar", forHTTPHeaderField: "Accept")
        if conditional, let v = validators[id] {
            request.setValue(v.0, forHTTPHeaderField: "If-None-Match"); request.setValue(v.1, forHTTPHeaderField: "If-Modified-Since")
        }
        let data: Data, response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw CalendarIssue.message("No pude contactar con Google Calendar. Revisa tu conexión; volveré a intentarlo automáticamente.") }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw CalendarIssue.message("Google no entregó una respuesta de calendario válida.") }
        // Keep raw ICS locally in memory, so a 304 can still expand newly upcoming recurring events.
        if http.statusCode == 304, let raw = rawCalendars[id] {
            let parser = self.parser; return try await work { try parser.parse(raw, now: now, feedID: id, name: name) }
        }
        guard http.statusCode == 200 else {
            throw CalendarIssue.message([401,403,404].contains(http.statusCode) ? "Google no permitió leer el calendario. Comprueba si el enlace fue cambiado o si tu organización restringe iCal." : "Google Calendar no está disponible en este momento. Volveré a intentarlo automáticamente.")
        }
        guard data.count <= 10 * 1024 * 1024, let text = String(data: data, encoding: .utf8) else { throw CalendarIssue.message("El calendario es demasiado grande o no tiene formato de texto válido.") }
        let parser = self.parser
        let result = try await work { try parser.parse(text, now: now, feedID: id, name: name) }
        try Task.checkCancellation()
        validators[id] = (http.value(forHTTPHeaderField: "ETag"), http.value(forHTTPHeaderField: "Last-Modified"))
        rawCalendars[id] = text
        return result
    }
    private var rawCalendars: [UUID: String] = [:]
}

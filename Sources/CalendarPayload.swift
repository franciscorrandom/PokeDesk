import Foundation

enum CalendarPayload {
    static let maximumBytes = 50 * 1024 * 1024
    static var sizeIssue: CalendarIssue { .message("El calendario supera el límite de 50 MB. Reduce su historial o conecta un calendario del trabajo más acotado.") }

    // A nonisolated async reader keeps large transfers away from the UI actor and
    // cancels at the limit rather than downloading an unbounded response first.
    static func receive(session: URLSession, request: URLRequest) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (Data(), response) }
        guard response.expectedContentLength <= Int64(maximumBytes) else { throw sizeIssue }
        var data = Data()
        data.reserveCapacity(min(maximumBytes, max(65536, Int(response.expectedContentLength))))
        for try await byte in bytes {
            if data.count >= maximumBytes { throw sizeIssue }
            data.append(byte)
        }
        try Task.checkCancellation()
        return (data, response)
    }

    static func decode(_ data: Data, contentType: String? = nil) throws -> String {
        guard data.count <= maximumBytes else { throw sizeIssue }
        let charset = (contentType ?? "").lowercased().split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }.first { $0.hasPrefix("charset=") }?
            .dropFirst(8).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
        var text: String?
        if data.starts(with: [0xff, 0xfe]) || data.starts(with: [0xfe, 0xff]) {
            text = String(data: data, encoding: .utf16)
        } else if charset == "utf-16le" { text = String(data: data, encoding: .utf16LittleEndian) }
        else if charset == "utf-16be" { text = String(data: data, encoding: .utf16BigEndian) }
        else { text = String(data: data, encoding: .utf8) }
        if text == nil {
            // Some exporters fold in the middle of a multi-byte UTF-8 character.
            // Unfold those raw bytes before trying UTF-8 again (RFC 5545 §3.1).
            let source = Array(data); var unfolded = Data(); unfolded.reserveCapacity(source.count)
            var i = 0
            while i < source.count {
                if i + 2 < source.count, source[i] == 13, source[i + 1] == 10, [9, 32].contains(source[i + 2]) { i += 3 }
                else { unfolded.append(source[i]); i += 1 }
            }
            text = String(data: unfolded, encoding: .utf8)
            if text == nil && ["iso-8859-1", "latin1", "latin-1"].contains(charset ?? "") { text = String(data: data, encoding: .isoLatin1) }
            if text == nil && ["windows-1252", "cp1252"].contains(charset ?? "") { text = String(data: data, encoding: .windowsCP1252) }
        }
        guard var text, !text.contains("\0") else {
            throw CalendarIssue.message("Google entregó un calendario con una codificación de texto no compatible. Comprueba la dirección secreta iCal o vuelve a generarla.")
        }
        if text.hasPrefix("\u{feff}") { text.removeFirst() }
        guard text.contains("BEGIN:VCALENDAR") else {
            throw CalendarIssue.message("El enlace devolvió una página u otro archivo en lugar de un calendario iCal. Revisa la dirección secreta y si tu organización permite compartir el calendario por iCal.")
        }
        return text
    }
}

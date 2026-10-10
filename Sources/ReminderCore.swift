import Foundation

struct CalendarFeed: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var lastUpdated: Date?
}


struct DailyTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var hour: Int
    var minute: Int
    var repeatsDaily = true
    var weekdaysOnly = true
    var createdAt = Date()
    var completedOn: String?
    var completedAt: Date?
    var lastRemindedOn: String?

    func isComplete(at now: Date, calendar: Calendar = .current) -> Bool {
        repeatsDaily ? completedOn == ReminderRules.dayKey(now, calendar: calendar) : completedAt != nil
    }

    func dueDate(at now: Date, calendar: Calendar = .current) -> Date? {
        let base = repeatsDaily ? now : createdAt
        if repeatsDaily && weekdaysOnly && calendar.isDateInWeekend(now) { return nil }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base)
    }

    func shouldRemind(at now: Date, calendar: Calendar = .current) -> Bool {
        guard !isComplete(at: now, calendar: calendar), now >= createdAt,
              let due = dueDate(at: now, calendar: calendar), due <= now else { return false }
        let key = repeatsDaily ? ReminderRules.dayKey(now, calendar: calendar) : "once"
        return lastRemindedOn != key
    }
}

struct Meeting: Identifiable, Codable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var calendarName: String
    var joinURL: URL?
    var allDay: Bool
}

struct PetAlert: Identifiable, Codable {
    var id = UUID()
    var title: String
    var message: String
    var taskID: UUID?
    var meetingID: String?
    var joinURL: URL?
    var dueAt: Date
    var focusTimerID: UUID?
}

struct PetSettings: Codable {
    var tasks: [DailyTask] = []
    var calendarFeeds: [CalendarFeed]?
    var meetingLeadMinutes = 10
    var petSize: Double = 166
    var soundEnabled = true
    var motionEnabled = true
    var positionX: Double?
    var positionY: Double?
    var petYaw: Double?
    var petCharacter: String?
    var characterYaws: [String: Double]?
    var firedMeetings: [String: Date] = [:]
    var snoozed: [PetAlert] = []
    var pausedUntil: Date?
    var focusTimer: FocusTimer?
    var voice: VoicePreferences?
    // Optional for compatibility with state files saved before notes existed.
    var notes: [PetNote]?
    var character: PetCharacter { PetCharacter(rawValue: petCharacter ?? "") ?? .arcanine }
    var characterYaw: Double { characterYaws?[character.rawValue] ?? (character == .arcanine ? petYaw ?? 0 : 0) }
    mutating func setCharacterYaw(_ angle: Double) {
        let selected = character
        if characterYaws == nil { characterYaws = [:] }
        characterYaws?[selected.rawValue] = PetRotation.normalized(angle)
        if selected == .arcanine { petYaw = PetRotation.normalized(angle) }
    }
}

struct NoteRevision: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var body: String
    var category: String?
    var savedAt: Date
}

struct PetNote: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var body: String
    var category: String?
    var createdAt: Date
    var updatedAt: Date
    var archivedAt: Date?
    var revisions: [NoteRevision] = []
    var displayTitle: String {
        title.isEmpty ? String((body.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Nota").prefix(60)) : title
    }
}

struct NoteDraft: Equatable {
    var id: UUID?
    var title = ""
    var body = ""
    var category = ""
    var canSave: Bool { !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum NoteRules {
    static func category(_ value: String) -> String? {
        let cleaned = value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned.isEmpty ? nil : cleaned
    }
    static func key(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "es"))
    }
    static func categories(in notes: [PetNote]) -> [String] {
        var seen = Set<String>()
        return notes.compactMap(\.category).filter { seen.insert(key($0)).inserted }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    static func filtered(_ notes: [PetNote], query: String = "", category: String? = nil, archived: Bool = false) -> [PetNote] {
        let search = key(query.trimmingCharacters(in: .whitespacesAndNewlines))
        return notes.filter { note in
            (note.archivedAt != nil) == archived &&
            (category == nil || key(note.category ?? "") == key(category!)) &&
            (search.isEmpty || key([note.title, note.body, note.category ?? ""].joined(separator: "\n")).contains(search))
        }.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

struct FocusTimer: Codable, Equatable {
    enum Phase: String, Codable { case running, paused, finished }
    var id = UUID()
    var durationSeconds: Int
    var deadline: Date
    var phase: Phase = .running
    var pausedSeconds: TimeInterval = 0
    var notified = false

    init(minutes: Int, now: Date = Date()) {
        durationSeconds = max(1, min(180, minutes)) * 60
        deadline = now.addingTimeInterval(Double(durationSeconds))
    }

    func remaining(at now: Date) -> Int {
        switch phase {
        case .running: return max(0, Int(ceil(deadline.timeIntervalSince(now))))
        case .paused: return max(0, Int(ceil(pausedSeconds)))
        case .finished: return 0
        }
    }

    func display(at now: Date) -> String {
        let seconds = remaining(at: now)
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func showsOnFace(at now: Date) -> Bool { phase != .finished && remaining(at: now) > 0 }

    func progress(at now: Date) -> Double { min(1, max(0, 1 - Double(remaining(at: now)) / Double(durationSeconds))) }

    mutating func pause(at now: Date) {
        guard phase == .running, remaining(at: now) > 0 else { return }
        pausedSeconds = max(0, deadline.timeIntervalSince(now))
        phase = .paused
    }

    mutating func resume(at now: Date) {
        guard phase == .paused else { return }
        deadline = now.addingTimeInterval(pausedSeconds)
        phase = .running
    }
}

enum EnglishVoice: String, CaseIterable, Identifiable {
    case gracie, holden
    var id: String { rawValue }
    var name: String { self == .gracie ? "Gracie" : "Holden" }
    var providerVoiceID: String {
        self == .gracie ? "09878754-f20b-5330-9790-58a8027ab5b2" : "3c9d6053-6334-592c-8997-4e325286af3f"
    }
}

struct VoicePreferences: Codable {
    var enabled = true
    var userName = ""
    var voiceID: String?
    var englishVoice: String?
    var volume = 0.7
    var assistantTone = true
    var speakMeetings = true
    var speakTasks = true
    var speakTimers = true
    var selectedEnglishVoice: EnglishVoice { EnglishVoice(rawValue: englishVoice ?? "") ?? .holden }
}

enum VoiceClip: String, CaseIterable {
    case focus5, focus10, focus30, focusOther, focusFinished, meetingWithLink, meeting, task, preview

    var phrase: String {
        switch self {
        case .focus5: return "Your five minutes of focus start now. I'll let you know when it's time for a break."
        case .focus10: return "Your ten minutes of focus start now. I'll let you know when it's time for a break."
        case .focus30: return "Your thirty minutes of focus start now. I'll let you know when it's time for a break."
        case .focusOther: return "Your focus session starts now. I'll let you know when it's time for a break."
        case .focusFinished: return "Your focus session is complete. It's time for a break."
        case .meetingWithLink, .meeting: return "Your meeting starts soon."
        case .task: return "You have a task reminder. Please check the details on my screen."
        case .preview: return "Your five minutes of focus start now. Your next meeting begins in ten minutes. The link is in my notification. Remember to check your tasks for today."
        }
    }

    static func focusStart(minutes: Int) -> VoiceClip {
        switch minutes { case 5: return .focus5; case 10: return .focus10; case 30: return .focus30; default: return .focusOther }
    }

    static func reminder(_ alert: PetAlert, preferences: VoicePreferences) -> VoiceClip? {
        guard preferences.enabled else { return nil }
        if alert.focusTimerID != nil { return preferences.speakTimers ? .focusFinished : nil }
        if alert.meetingID != nil { return preferences.speakMeetings ? (alert.joinURL == nil ? .meeting : .meetingWithLink) : nil }
        if alert.taskID != nil { return preferences.speakTasks ? .task : nil }
        return .preview
    }
}

enum FocusCommand {
    static func minutes(in text: String) -> Int? {
        let normalized = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_CL"))
        let pattern = #"(?<![\d.,])\b(\d{1,3})\s*(?:minutos?|minutes?|min|m)\b"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
           let range = Range(match.range(at: 1), in: normalized), let number = Int(normalized[range]), (1...180).contains(number) { return number }
        if let number = Int(normalized.trimmingCharacters(in: .whitespacesAndNewlines)), (1...180).contains(number) { return number }
        let words = ["cinco": 5, "diez": 10, "quince": 15, "veinte": 20, "veinticinco": 25, "treinta": 30, "sesenta": 60]
        for (word, minutes) in words {
            if normalized.range(of: "\\b\(word)\\s+minutos?\\b", options: .regularExpression) != nil { return minutes }
        }
        return nil
    }
}

enum ReminderRules {
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func meetingKey(_ meeting: Meeting, leadMinutes: Int) -> String {
        "\(meeting.id)|\(Int(meeting.start.timeIntervalSince1970))|\(leadMinutes)"
    }

    static func shouldRemind(_ meeting: Meeting, now: Date, leadMinutes: Int, fired: [String: Date]) -> Bool {
        guard !meeting.allDay, meeting.end > now, meeting.start >= now.addingTimeInterval(-60) else { return false }
        let notifyAt = meeting.start.addingTimeInterval(-Double(leadMinutes) * 60)
        return now >= notifyAt && fired[meetingKey(meeting, leadMinutes: leadMinutes)] == nil
    }

    static func meetingMessage(_ meeting: Meeting, now: Date) -> String {
        let minutes = Int(ceil(meeting.start.timeIntervalSince(now) / 60))
        return minutes > 0 ? "Empieza en \(minutes) min · \(time(meeting.start))" : "Está empezando · \(time(meeting.start))"
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_CL")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func joinURL(in strings: [String]) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let hosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com", "teams.cloud.microsoft", "webex.com"]
        for text in strings {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let url = match.url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
                      hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { continue }
                return url
            }
        }
        return nil
    }
}

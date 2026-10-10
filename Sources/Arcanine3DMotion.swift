import Foundation

enum ArcanineClip: String, CaseIterable {
    case idle = "reposo", curious = "curiosidad", greeting = "saludo", happyTail = "cola-alegre"
    case sniff = "olfateo", stretch = "estiramiento", alert = "aviso-reunion"
    case celebration = "celebracion", chaseTail = "giro-rapido"
    case petting = "caricias", sit = "sentarse"
    var duration: TimeInterval {
        switch self {
        case .idle: return 8
        case .happyTail: return 4.8
        case .stretch: return 5
        case .celebration: return 3.6
        case .petting: return 5.6
        case .sit: return 7.2
        default: return 4
        }
    }
    var title: String {
        switch self {
        case .idle: return "Reposo y parpadeo"
        case .curious: return "Cabeza curiosa"
        case .greeting: return "Saludo con la pata"
        case .happyTail: return "Cola alegre"
        case .sniff: return "Olfateo"
        case .stretch: return "Estiramiento"
        case .alert: return "Aviso atento"
        case .celebration: return "Celebración"
        case .chaseTail: return "Persiguiendo su cola"
        case .petting: return "Disfrutar las caricias"
        case .sit: return "Sentarse"
        }
    }
    var priority: Int { self == .alert ? 3 : self == .celebration ? 2 : self == .idle ? 0 : 1 }
}

/// Chooses gestures independently of rendering, so alerts can interrupt play and focus stays calm.
struct Arcanine3DMotion {
    private(set) var clip: ArcanineClip = .idle
    private(set) var startedAt: TimeInterval = 0
    private(set) var revision = 0
    private var lastOptional: ArcanineClip?
    private var lastChase = -Double.infinity
    private var nextGesture: TimeInterval = 18
    private var pending: ArcanineClip?
    private var enabled = true
    var focusing = false
    var alerting = false

    mutating func setEnabled(_ value: Bool, at now: TimeInterval) {
        guard enabled != value else { return }
        enabled = value; pending = nil
        start(.idle, at: now)
    }
    mutating func request(_ value: ArcanineClip, at now: TimeInterval, manual: Bool = false) {
        guard enabled else { return }
        if !manual {
            if value == .chaseTail && (focusing || now - lastChase < 180) { return }
            if clip != .idle && value.priority < clip.priority {
                if value == .celebration { pending = value }
                return
            }
        }
        start(value, at: now)
    }
    mutating func click(at now: TimeInterval) {
        var choices: [ArcanineClip] = [.curious, .greeting, .happyTail, .sniff, .stretch]
        if !focusing && now - lastChase >= 180 { choices.append(.chaseTail) }
        choices.removeAll { $0 == lastOptional }
        if let choice = choices.randomElement() { request(choice, at: now) }
    }
    mutating func tick(at now: TimeInterval) {
        guard enabled else { return }
        if clip != .idle && now - startedAt >= clip.duration {
            if let queued = pending { pending = nil; start(queued, at: now) }
            else { start(.idle, at: now) }
        }
        if clip == .idle && now >= nextGesture && !alerting {
            var choices: [ArcanineClip] = focusing ? [.curious, .sniff] : [.curious, .happyTail, .sniff, .stretch]
            choices.removeAll { $0 == lastOptional }
            if let choice = choices.randomElement() { start(choice, at: now) }
        }
    }
    private mutating func start(_ value: ArcanineClip, at now: TimeInterval) {
        clip = value; startedAt = now; revision += 1
        if value.priority == 1 { lastOptional = value }
        if value == .chaseTail { lastChase = now }
        nextGesture = now + value.duration + (focusing ? Double.random(in: 75...110) : Double.random(in: 18...35))
    }
}

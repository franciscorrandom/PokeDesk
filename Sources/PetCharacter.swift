import Foundation

/// Data belongs to the app; a companion changes its appearance and gestures.
enum PetCharacter: String, CaseIterable, Identifiable {
    case arcanine, mewtwo, pikachu, charizard
    var id: String { rawValue }
    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    var number: String { switch self { case .arcanine: return "059"; case .mewtwo: return "150"; case .pikachu: return "025"; case .charizard: return "006" } }
    var typeName: String { switch self { case .arcanine: return "FUEGO"; case .mewtwo: return "PSÍQUICO"; case .pikachu: return "ELÉCTRICO"; case .charizard: return "FUEGO / VOLADOR" } }
    var symbol: String { switch self { case .arcanine, .charizard: return "flame.fill"; case .mewtwo: return "sparkles"; case .pikachu: return "bolt.fill" } }
    var thumbnailResource: String { "preview-\(rawValue)" }
    var modelResource: String { "\(rawValue)-biblioteca" }
    var clips: [ArcanineClip] { self == .arcanine ? ArcanineClip.allCases : ArcanineClip.allCases.filter { $0 != .sniff && $0 != .chaseTail } }
    var description: String {
        switch self {
        case .arcanine: return "Parpadea, saluda, olfatea, se estira y persigue su cola."
        case .mewtwo: return "Levita, parpadea, saluda, mueve su cola y reacciona con gestos psíquicos."
        case .pikachu: return "Parpadea, mueve sus orejas y cola, saluda y disfruta las caricias."
        case .charizard: return "Parpadea, respira, mueve las alas y cola, saluda y descansa."
        }
    }
    func title(for clip: ArcanineClip) -> String {
        guard self != .arcanine else { return clip.title }
        switch clip {
        case .idle: return self == .mewtwo ? "Levitación y parpadeo" : self == .pikachu ? "Orejas y parpadeo" : "Respiración y parpadeo"
        case .greeting: return "Saludo con la mano"
        case .curious: return "Mirada curiosa"
        case .happyTail: return self == .charizard ? "Alas y cola" : "Cola en movimiento"
        case .alert: return self == .mewtwo ? "Aviso psíquico" : "Aviso atento"
        case .sit: return self == .mewtwo ? "Meditación" : "Descansar"
        default: return clip.title
        }
    }
    func isAvailable(in bundle: Bundle = .main) -> Bool { bundle.url(forResource: modelResource, withExtension: "glb") != nil }
}

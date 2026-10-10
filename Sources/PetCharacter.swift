import Foundation

/// The assistant's data belongs to the app; a character changes only its appearance and gestures.
enum PetCharacter: String, CaseIterable, Identifiable {
    case arcanine, mewtwo
    var id: String { rawValue }
    var name: String { self == .arcanine ? "Arcanine" : "Mewtwo" }
    var number: String { self == .arcanine ? "059" : "150" }
    var typeName: String { self == .arcanine ? "FUEGO" : "PSÍQUICO" }
    var symbol: String { self == .arcanine ? "flame.fill" : "sparkles" }
    var modelResource: String { "\(rawValue)-biblioteca" }
    var clips: [ArcanineClip] {
        self == .arcanine ? ArcanineClip.allCases : ArcanineClip.allCases.filter { $0 != .sniff && $0 != .chaseTail }
    }
    var description: String {
        self == .arcanine
            ? "Parpadea, saluda, olfatea, se estira y persigue su cola."
            : "Levita, parpadea, saluda, mueve su cola y reacciona con gestos psíquicos."
    }
    func title(for clip: ArcanineClip) -> String {
        guard self == .mewtwo else { return clip.title }
        switch clip {
        case .idle: return "Levitación y parpadeo"
        case .greeting: return "Saludo con la mano"
        case .curious: return "Mirada curiosa"
        case .happyTail: return "Cola en movimiento"
        case .alert: return "Aviso psíquico"
        case .petting: return "Disfrutar las caricias"
        case .sit: return "Meditación"
        default: return clip.title
        }
    }
    func isAvailable(in bundle: Bundle = .main) -> Bool {
        bundle.url(forResource: modelResource, withExtension: "glb") != nil
    }
}

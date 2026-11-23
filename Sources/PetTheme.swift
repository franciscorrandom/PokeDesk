import SwiftUI

/// A shared palette for every surface, including nested cards and button styles.
struct PetTheme {
    let character: PetCharacter
    private var dragonite: Bool { character == .dragonite }
    private var eevee: Bool { character == .eevee }
    private var plant: Bool { character == .bulbasaur }
    private var electric: Bool { character == .pikachu }
    private var dragon: Bool { character == .charizard }
    private var psychic: Bool { character == .mewtwo }
    private var aura: Bool { character == .lucario }
    private var ghost: Bool { character == .gengar }
    var red: Color { dragonite ? Color(red: 0.66, green: 0.36, blue: 0.13) : eevee ? Color(red: 0.47, green: 0.32, blue: 0.22) : plant ? Color(red: 0.19, green: 0.45, blue: 0.34) : aura ? Color(red: 0.15, green: 0.40, blue: 0.63) : ghost ? Color(red: 0.43, green: 0.30, blue: 0.67) : electric ? Color(red: 0.55, green: 0.41, blue: 0.04) : dragon ? Color(red: 0.15, green: 0.42, blue: 0.46) : psychic ? Color(red: 0.50, green: 0.35, blue: 0.70) : Color(red: 0.66, green: 0.36, blue: 0.16) }
    var deepRed: Color { red }
    var fire: Color { dragonite || eevee || plant || aura || ghost ? red : psychic ? Color(red: 0.53, green: 0.30, blue: 0.68) : ArcanineTheme.fire }
    var gold: Color { dragonite ? Color(red: 0.52, green: 0.75, blue: 0.61) : eevee ? Color(red: 0.91, green: 0.81, blue: 0.62) : plant ? Color(red: 0.66, green: 0.83, blue: 0.55) : aura ? Color(red: 0.60, green: 0.82, blue: 0.96) : ghost ? Color(red: 0.73, green: 0.64, blue: 0.90) : electric ? Color(red: 0.98, green: 0.79, blue: 0.20) : dragon ? Color(red: 0.96, green: 0.57, blue: 0.26) : psychic ? Color(red: 0.76, green: 0.65, blue: 0.91) : ArcanineTheme.gold }
    var ink: Color { Color(red: 0.15, green: 0.17, blue: 0.21) }
    var muted: Color { Color(red: 0.43, green: 0.47, blue: 0.53) }
    var paper: Color { .white }
    var card: Color { Color(red: 0.965, green: 0.970, blue: 0.980) }
    var line: Color { Color(red: 0.90, green: 0.92, blue: 0.95) }
    var accentSoft: Color { dragonite ? Color(red: 1, green: 0.95, blue: 0.87) : eevee ? Color(red: 0.97, green: 0.94, blue: 0.88) : plant ? Color(red: 0.91, green: 0.97, blue: 0.91) : aura ? Color(red: 0.91, green: 0.96, blue: 1) : ghost ? Color(red: 0.94, green: 0.92, blue: 0.98) : electric ? Color(red: 1, green: 0.97, blue: 0.85) : dragon ? Color(red: 0.90, green: 0.97, blue: 0.97) : psychic ? Color(red: 0.95, green: 0.93, blue: 0.98) : Color(red: 1, green: 0.955, blue: 0.90) }
    var blue: Color { dragonite ? Color(red: 0.22, green: 0.48, blue: 0.37) : eevee ? Color(red: 0.47, green: 0.32, blue: 0.22) : psychic ? Color(red: 0.31, green: 0.39, blue: 0.68) : ArcanineTheme.blue }
    var green: Color { ArcanineTheme.green }
}

private struct PetThemeKey: EnvironmentKey {
    static let defaultValue = PetTheme(character: .arcanine)
}
extension EnvironmentValues {
    var petTheme: PetTheme {
        get { self[PetThemeKey.self] }
        set { self[PetThemeKey.self] = newValue }
    }
}

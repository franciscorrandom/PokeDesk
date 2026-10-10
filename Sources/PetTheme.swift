import SwiftUI

/// A shared palette for every surface, including nested cards and button styles.
struct PetTheme {
    let character: PetCharacter
    private var psychic: Bool { character == .mewtwo }
    var red: Color { psychic ? Color(red: 0.43, green: 0.25, blue: 0.64) : ArcanineTheme.red }
    var deepRed: Color { psychic ? Color(red: 0.29, green: 0.15, blue: 0.45) : ArcanineTheme.deepRed }
    var fire: Color { psychic ? Color(red: 0.53, green: 0.30, blue: 0.68) : ArcanineTheme.fire }
    var gold: Color { psychic ? Color(red: 0.76, green: 0.65, blue: 0.91) : ArcanineTheme.gold }
    var ink: Color { psychic ? Color(red: 0.20, green: 0.15, blue: 0.26) : ArcanineTheme.ink }
    var muted: Color { psychic ? Color(red: 0.41, green: 0.36, blue: 0.47) : ArcanineTheme.muted }
    var paper: Color { psychic ? Color(red: 0.95, green: 0.93, blue: 0.99) : ArcanineTheme.paper }
    var card: Color { psychic ? Color(red: 0.99, green: 0.98, blue: 1.0) : ArcanineTheme.card }
    var line: Color { psychic ? Color(red: 0.77, green: 0.70, blue: 0.85) : ArcanineTheme.line }
    var blue: Color { psychic ? Color(red: 0.31, green: 0.39, blue: 0.68) : ArcanineTheme.blue }
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

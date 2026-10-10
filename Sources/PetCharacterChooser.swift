import AppKit
import SwiftUI

struct PetCharacterChooser: View {
    @Environment(\.petTheme) private var theme
    let selected: PetCharacter
    let onSelect: (PetCharacter) -> Void
    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(PetCharacter.allCases) { character in
                let chosen = character == selected
                Button { onSelect(character) } label: {
                    VStack(spacing: 5) {
                        if let art = NSImage(named: character.rawValue) {
                            Image(nsImage: art).resizable().scaledToFit().frame(height: 64)
                        } else { Image(systemName: character.symbol).font(.system(size: 32)).frame(height: 64) }
                        Text(character.name).font(.system(size: 13, weight: .bold, design: .rounded))
                        Text(chosen ? "Tu compañero" : "Elegir").font(.system(size: 10, weight: .semibold))
                    }.frame(maxWidth: .infinity).padding(10)
                        .foregroundStyle(chosen ? theme.red : theme.ink)
                        .background(chosen ? theme.red.opacity(0.09) : theme.card)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(chosen ? theme.red : theme.line, lineWidth: chosen ? 2 : 1))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).disabled(!character.isAvailable())
                    .accessibilityLabel("\(character.name), \(chosen ? "elegido" : "elegir compañero")")
            }
        }
    }
}

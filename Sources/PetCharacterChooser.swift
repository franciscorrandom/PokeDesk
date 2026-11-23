import AppKit
import SwiftUI

struct PetCharacterChooser: View {
    @Environment(\.petTheme) private var theme
    var compact = false
    let selected: PetCharacter
    let onSelect: (PetCharacter) -> Void
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
            ForEach(PetCharacter.allCases) { character in
                let chosen = character == selected
                Button { onSelect(character) } label: {
                    VStack(spacing: 5) {
                        if let url = Bundle.main.url(forResource: character.thumbnailResource, withExtension: "png"), let art = NSImage(contentsOf: url) {
                            Image(nsImage: art).resizable().scaledToFit().frame(height: compact ? 52 : 64)
                        } else { Image(systemName: character.symbol).font(.system(size: 32)).frame(height: compact ? 52 : 64) }
                        Text(character.name).font(.system(size: compact ? 12 : 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                        Text(chosen ? (compact ? "Elegido" : "Tu compañero") : "Elegir").font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    }.frame(maxWidth: .infinity).padding(compact ? 7 : 10)
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

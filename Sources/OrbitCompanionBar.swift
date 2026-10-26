import SwiftUI
import AppKit

private enum OrbitThumbnails {
    static let images: [PetCharacter: NSImage] = Dictionary(uniqueKeysWithValues: PetCharacter.allCases.compactMap { character in
        guard let url = Bundle.main.url(forResource: character.thumbnailResource, withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        return (character, image)
    })
}

struct OrbitThumbnail: View {
    let character: PetCharacter
    var body: some View {
        if let image = OrbitThumbnails.images[character] {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
        } else {
            Image(systemName: character.symbol).resizable().scaledToFit()
        }
    }
}

struct OrbitCompanionBar: View {
    @Environment(\.petTheme) private var theme
    @ObservedObject var model: PetModel
    var body: some View {
        HStack(spacing: 10) {
            OrbitThumbnail(character: model.settings.character).frame(width: 43, height: 43)
                .padding(4).background(theme.accentSoft).clipShape(RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(model.settings.character.name).font(.system(size: 14, weight: .semibold))
                Text("Tu compañero de escritorio").font(.system(size: 11)).foregroundStyle(theme.muted)
            }
            Spacer(minLength: 6)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(35), spacing: 5), count: 3), spacing: 5) {
                ForEach(PetCharacter.allCases) { character in
                    Button { model.selectCharacter(character) } label: {
                        OrbitThumbnail(character: character).frame(width: 29, height: 31).padding(3)
                            .background(character == model.settings.character ? theme.accentSoft : theme.card)
                            .clipShape(RoundedRectangle(cornerRadius: 11))
                            .overlay(RoundedRectangle(cornerRadius: 11).stroke(character == model.settings.character ? theme.red.opacity(0.5) : .clear, lineWidth: 1))
                    }.buttonStyle(.plain).disabled(!character.isAvailable())
                        .help("Elegir a \(character.name)")
                        .accessibilityLabel("Elegir a \(character.name)")
                }
            }.frame(width: 115)
        }.padding(.horizontal, 21).padding(.vertical, 14)
    }
}

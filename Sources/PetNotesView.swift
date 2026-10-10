import SwiftUI

private enum NoteCategoryFilter: Hashable {
    case all, uncategorized, named(String)
    var category: String? {
        switch self { case .all: return nil; case .uncategorized: return ""; case .named(let value): return value }
    }
}

struct PetNoteEditor: View {
    @ObservedObject var model: PetModel
    var compact = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Título (opcional)", text: $model.noteDraft.title)
                .font(.system(size: 13, weight: .semibold)).accessibilityLabel("Título de la nota")
                .textFieldStyle(.plain).padding(9).background(ArcanineTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
            ZStack(alignment: .topLeading) {
                if model.noteDraft.body.isEmpty {
                    Text("Escribe una idea, un pendiente o lo que quieras recordar…")
                        .font(.system(size: 12)).foregroundStyle(ArcanineTheme.muted).padding(.horizontal, 8).padding(.top, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $model.noteDraft.body)
                    .font(.system(size: 13)).scrollContentBackground(.hidden).padding(3)
                    .accessibilityLabel("Contenido de la nota")
            }.frame(height: compact ? 78 : 84).background(ArcanineTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(ArcanineTheme.line, lineWidth: 1))
            HStack(spacing: 7) {
                Image(systemName: "tag").foregroundStyle(ArcanineTheme.red)
                TextField("Categoría (opcional)", text: $model.noteDraft.category)
                    .textFieldStyle(.plain).font(.system(size: 12)).accessibilityLabel("Categoría de la nota")
                if !model.noteCategories.isEmpty {
                    Menu {
                        Button("Sin categoría") { model.noteDraft.category = "" }
                        ForEach(model.noteCategories, id: \.self) { category in
                            Button(category) { model.noteDraft.category = category }
                        }
                    } label: { Text("Elegir").font(.system(size: 10)) }
                        .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("Elegir categoría existente")
                }
            }.padding(9).background(ArcanineTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 8) {
                Button(model.noteDraft.id == nil ? "Guardar nota" : "Guardar cambios") { model.saveNote() }
                    .buttonStyle(PokedexButtonStyle(prominent: true))
                    .disabled(!model.noteDraft.canSave || !model.noteHasChanges)
                if model.noteDraft.id != nil {
                    Button("Nueva nota") { model.newNote() }
                } else if model.noteDraft.canSave || !model.noteDraft.title.isEmpty || !model.noteDraft.category.isEmpty {
                    Button("Limpiar") { model.newNote() }
                }
                Spacer(minLength: 0)
            }
            if let message = model.noteFeedback {
                Label(message, systemImage: message.hasPrefix("No ") ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.system(size: 10)).foregroundStyle(message.hasPrefix("No ") ? ArcanineTheme.red : ArcanineTheme.green)
                    .fixedSize(horizontal: false, vertical: true).accessibilityLabel(message)
            } else if let note = model.editingNote {
                Text("Último guardado: \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10)).foregroundStyle(ArcanineTheme.muted)
            } else if !compact {
                Text("La categoría es opcional. Guarda la nota para conservarla.")
                    .font(.system(size: 10)).foregroundStyle(ArcanineTheme.muted)
            }
        }
    }
}

struct PetNotesView: View {
    @ObservedObject var model: PetModel
    @State private var query = ""
    @State private var category = NoteCategoryFilter.all
    @State private var showArchived = false
    private var filtered: [PetNote] {
        NoteRules.filtered(model.notes, query: query, category: category.category, archived: showArchived)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tu cuaderno", systemImage: "note.text")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Spacer()
                Button { model.newNote() } label: { Label("Nueva", systemImage: "plus") }.help("Escribir una nueva nota")
            }
            PetNoteEditor(model: model).padding(12).background(ArcanineTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(ArcanineTheme.gold.opacity(0.6), lineWidth: 1))
            if let note = model.editingNote, !note.revisions.isEmpty {
                DisclosureGroup("Versiones anteriores (\(note.revisions.count))") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(note.revisions.reversed())) { revision in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(revision.savedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                                    .font(.system(size: 10, weight: .medium)).foregroundStyle(ArcanineTheme.red)
                                if !revision.title.isEmpty { Text(revision.title).font(.system(size: 12, weight: .semibold)) }
                                if let category = revision.category { Label(category, systemImage: "tag").font(.system(size: 10)).foregroundStyle(ArcanineTheme.muted) }
                                Text(revision.body).font(.system(size: 12)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
                                .background(ArcanineTheme.card).clipShape(RoundedRectangle(cornerRadius: 9))
                        }
                    }.padding(.top, 10)
                }.font(.system(size: 12, weight: .semibold)).padding(12)
                    .background(ArcanineTheme.line.opacity(0.18)).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            HStack {
                Text("HISTORIAL").font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
                Spacer()
                Text("\(filtered.count) \(filtered.count == 1 ? "nota" : "notas")")
                    .font(.system(size: 10)).foregroundStyle(ArcanineTheme.muted)
            }
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(ArcanineTheme.muted)
                TextField("Buscar en tus notas", text: $query).textFieldStyle(.plain).font(.system(size: 12))
                    .accessibilityLabel("Buscar notas")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).accessibilityLabel("Limpiar búsqueda")
                }
            }.padding(10).background(ArcanineTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack {
                Picker("Categoría", selection: $category) {
                    Text("Todas").tag(NoteCategoryFilter.all)
                    Text("Sin categoría").tag(NoteCategoryFilter.uncategorized)
                    ForEach(model.noteCategories, id: \.self) { value in Text(value).tag(NoteCategoryFilter.named(value)) }
                }.font(.system(size: 11))
                Toggle("Archivadas", isOn: $showArchived).toggleStyle(.checkbox).font(.system(size: 11)).fixedSize()
            }
            if filtered.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.notes.isEmpty ? "Tu primera idea empieza aquí" : "No hay notas en esta vista", systemImage: "book.closed")
                        .font(.system(size: 13, weight: .semibold))
                    Text(model.notes.isEmpty ? "Escribe arriba y guarda tu nota. La encontrarás aquí cuando vuelvas." : "Prueba otra búsqueda, categoría o revisa las archivadas.")
                        .font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted)
                }.padding(12)
            }
            ForEach(filtered) { note in
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        Text(note.displayTitle).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(2)
                        Spacer(minLength: 4)
                        if note.archivedAt == nil {
                            Button { model.setNoteArchived(note.id, archived: true) } label: { Image(systemName: "archivebox") }
                                .help("Archivar · podrás recuperar esta nota").accessibilityLabel("Archivar: \(note.displayTitle)")
                        }
                    }
                    Text(note.body).font(.system(size: 12)).foregroundStyle(ArcanineTheme.muted).lineLimit(3)
                    HStack(spacing: 5) {
                        Label(note.category ?? "Sin categoría", systemImage: "tag")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(ArcanineTheme.red).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(note.updatedAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                            .font(.system(size: 9)).foregroundStyle(ArcanineTheme.muted)
                    }
                    HStack {
                        if note.archivedAt == nil {
                            Button("Leer / editar") { model.editNote(note.id) }.accessibilityLabel("Editar: \(note.displayTitle)")
                        } else {
                            Button("Recuperar") {
                                if model.setNoteArchived(note.id, archived: false) {
                                    showArchived = false
                                    model.editNote(note.id)
                                }
                            }
                                .accessibilityLabel("Recuperar: \(note.displayTitle)")
                        }
                        Spacer()
                        if !note.revisions.isEmpty {
                            Text("\(note.revisions.count + 1) versiones").font(.system(size: 10)).foregroundStyle(ArcanineTheme.muted)
                        }
                    }
                }.padding(12).background(ArcanineTheme.card).clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ArcanineTheme.line, lineWidth: 1))
            }
        }.id("notes-start")
    }
}

struct PetNotesQuickView: View {
    @ObservedObject var model: PetModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PetNoteEditor(model: model, compact: true)
            let recent = Array(NoteRules.filtered(model.notes).prefix(2))
            if !recent.isEmpty {
                Text("NOTAS RECIENTES").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(ArcanineTheme.muted)
                ForEach(recent) { note in
                    Button { model.editNote(note.id) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.displayTitle).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                Text(note.category ?? "Sin categoría").font(.system(size: 9)).foregroundStyle(ArcanineTheme.muted)
                            }
                            Spacer()
                            Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(ArcanineTheme.red)
                        }.padding(9).background(ArcanineTheme.card).clipShape(RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain).accessibilityLabel("Editar: \(note.displayTitle)")
                }
            }
        }
    }
}

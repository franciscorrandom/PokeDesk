import Foundation

var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
    checks += 1
}

Task { @MainActor in
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("arcanine-notes-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("estado.json")
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var legacy = PetSettings()
        legacy.tasks = [DailyTask(title: "Preparar reunión", hour: 10, minute: 30)]
        legacy.petYaw = 1.23
        legacy.calendarFeeds = [CalendarFeed(name: "Trabajo")]
        legacy.focusTimer = FocusTimer(minutes: 10, now: now)
        legacy.voice = VoicePreferences()
        legacy.voice?.englishVoice = "gracie"
        try JSONEncoder().encode(legacy).write(to: url)
        let model = PetModel(storageURL: url)
        check(model.notes.isEmpty && model.errorMessage == nil, "Leer estado anterior sin notas")
        check(!model.saveNote(now: now) && model.notes.isEmpty, "No guardar notas vacías")
        model.noteDraft.body = " \n \t"
        check(!model.saveNote(now: now), "No guardar solo espacios")
        model.noteDraft = NoteDraft(title: "  Ideas de reunión  ", body: "Línea uno\nLínea dos con ñ y café.\n", category: "  Reunión  ")
        check(model.saveNote(now: now), "Crear y guardar nota")
        let first = model.notes.first!
        check(first.title == "Ideas de reunión" && first.category == "Reunión", "Limpiar título y categoría")
        check(first.body == "Línea uno\nLínea dos con ñ y café.\n", "Conservar texto, Unicode y saltos de línea")
        check(first.createdAt == now && first.updatedAt == now && first.revisions.isEmpty, "Guardar fechas y una sola versión inicial")
        check(!model.noteHasChanges && model.noteFeedback == "Guardada en tu Mac", "Confirmar guardado solo después de escribir el archivo")
        let reopened = PetModel(storageURL: url)
        check(reopened.notes == model.notes, "Recuperar notas después de reiniciar")
        check(reopened.settings.tasks == legacy.tasks && reopened.settings.petYaw == legacy.petYaw, "Conservar tareas y orientación")
        check(reopened.settings.focusTimer == legacy.focusTimer && reopened.settings.calendarFeeds == legacy.calendarFeeds, "Conservar timer y calendario local")
        check(model.saveNote(now: now.addingTimeInterval(10)) && model.notes[0].revisions.isEmpty && model.notes[0].updatedAt == now, "Guardar sin cambios no añade versiones ni cambia la fecha")
        model.noteDraft.body = "Resumen nuevo\nEnviar las conclusiones."
        model.noteDraft.category = "Proyectos   del\n equipo"
        check(model.noteHasChanges && model.noteFeedback == nil, "Detectar cambios y limpiar confirmación anterior")
        check(model.saveNote(now: now.addingTimeInterval(60)), "Guardar edición")
        let changed = model.notes[0]
        check(changed.id == first.id && changed.createdAt == first.createdAt && changed.updatedAt == now.addingTimeInterval(60), "Editar conserva identidad y fecha inicial")
        check(changed.revisions.count == 1 && changed.revisions[0].body == first.body && changed.revisions[0].category == first.category && changed.revisions[0].savedAt == now, "Conservar contenido anterior y su categoría y fecha")
        check(changed.category == "Proyectos del equipo", "Normalizar espacios de categoría")
        model.newNote()
        model.noteDraft = NoteDraft(body: "Recordar una idea sin título\nSegunda línea")
        check(model.saveNote(now: now.addingTimeInterval(30)), "Guardar sin título ni categoría")
        let second = model.editingNote!
        check(second.title.isEmpty && second.category == nil && second.displayTitle == "Recordar una idea sin título", "Usar primera línea como título visible")
        check(NoteRules.filtered(model.notes).map(\.id) == [first.id, second.id], "Historial ordenado por último guardado")
        check(NoteRules.filtered(model.notes, query: "CONCLUSIONES", category: "proyectos del equipo").first?.id == first.id, "Buscar y filtrar juntos sin distinguir mayúsculas")
        check(NoteRules.filtered(model.notes, query: "titulo").first?.id == second.id, "Búsqueda ignora tildes")
        check(NoteRules.filtered(model.notes, category: "").map(\.id) == [second.id], "Filtrar sin categoría")
        model.newNote()
        model.noteDraft = NoteDraft(title: "Otro proyecto", body: "Una nota más", category: "PROYECTOS DEL EQUIPO")
        check(model.saveNote(now: now.addingTimeInterval(90)) && model.noteCategories == ["Proyectos del equipo"], "Reutilizar categoría existente aunque cambie la capitalización")
        check(model.editingNote?.category == "Proyectos del equipo", "Guardar nombre consistente de categoría")
        check(model.setNoteArchived(first.id, archived: true, now: now.addingTimeInterval(120)), "Archivar de forma reversible")
        check(NoteRules.filtered(model.notes).count == 2 && NoteRules.filtered(model.notes, archived: true).map(\.id) == [first.id], "Separar notas activas y archivadas")
        let archivedReload = PetModel(storageURL: url)
        check(archivedReload.notes.first(where: { $0.id == first.id })?.revisions == changed.revisions && archivedReload.notes.first(where: { $0.id == first.id })?.archivedAt != nil, "Archivo y versiones sobreviven al reinicio")
        check(model.setNoteArchived(first.id, archived: false), "Recuperar nota archivada")
        model.editNote(first.id)
        check(model.noteDraft.body == changed.body && model.noteDraft.id == first.id, "Recuperar texto completo para editar")
        model.noteDraft.body += "\nBorrador aún sin guardar."
        model.dashboardTab = 5
        check(model.noteDraft.body.hasSuffix("Borrador aún sin guardar."), "Compartir borrador entre tarjetas y panel")
        let unsavedReload = PetModel(storageURL: url)
        check(unsavedReload.notes.first(where: { $0.id == first.id })?.body == changed.body, "Cambios sin guardar no sobrescriben la nota guardada")
        model.editNote(first.id)
        model.noteDraft.body += "\nSegunda actualización."
        check(model.saveNote(now: now.addingTimeInterval(150)) && model.editingNote?.revisions.count == 2, "Guardar todas las versiones sucesivas")
        check(PetModel(storageURL: url).notes == model.notes, "Persistir historial completo tras ediciones y recuperación")
        let corruptURL = folder.appendingPathComponent("corrupto.json")
        let corrupt = Data("archivo original dañado".utf8)
        try corrupt.write(to: corruptURL)
        let protected = PetModel(storageURL: corruptURL)
        protected.noteDraft = NoteDraft(body: "Borrador conservado")
        check(!protected.saveNote() && protected.notes.isEmpty && protected.noteDraft.body == "Borrador conservado", "No anunciar guardado ante datos ilegibles; conservar borrador")
        let unchangedData = try Data(contentsOf: corruptURL)
        check(unchangedData == corrupt, "Nunca sobrescribir un estado ilegible")
        let blocked = folder.appendingPathComponent("ruta-ocupada")
        try Data("archivo".utf8).write(to: blocked)
        let failed = PetModel(storageURL: blocked.appendingPathComponent("estado.json"))
        failed.noteDraft = NoteDraft(body: "Nota que no se pudo guardar")
        check(!failed.saveNote() && failed.notes.isEmpty && failed.noteDraft.id == nil && failed.noteDraft.canSave, "Un error de escritura revierte la lista y conserva el texto para reintentar")
        check(failed.noteFeedback?.hasPrefix("No se pudo") == true, "Mostrar error y no confirmación de guardado falso")
        print("\(checks) comprobaciones de notas correctas: migración, persistencia, categorías, búsqueda, versiones, archivo y errores de escritura.")
        exit(0)
    } catch { print("Falló notas: \(error)"); exit(1) }
}
RunLoop.main.run()

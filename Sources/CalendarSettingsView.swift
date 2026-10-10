import SwiftUI

struct CalendarSettingsView: View {
    @ObservedObject var model: PetModel
    @State private var address = ""
    @State private var name = ""
    @State private var replacing: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(model.feeds.isEmpty ? "Bienvenido a Arcanine" : "Calendario por iCal", systemImage: "calendar").font(.headline)
            Text("Pega el enlace privado de Google Calendar y empieza a recibir avisos. Tareas, notas y concentración ya están disponibles.")
                .font(.system(size: 12)).foregroundStyle(ArcanineTheme.muted)
            SecureField("Dirección secreta en formato iCal", text: $address).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Enlace privado iCal")
            TextField("Nombre del calendario · opcional", text: $name).textFieldStyle(.roundedBorder)
            HStack {
                Button(replacing == nil ? "Conectar calendario" : "Actualizar enlace") {
                    model.subscribeCalendar(address, name: name, replacing: replacing)
                    address = ""; name = ""; replacing = nil
                }.buttonStyle(PokedexButtonStyle(prominent: true)).disabled(address.isEmpty || model.calendarBusy)
                if model.calendarBusy {
                    ProgressView().controlSize(.small)
                    Button("Cancelar") { model.cancelCalendarConnection() }
                }
            }
            Text(model.calendarMessage).font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted).fixedSize(horizontal: false, vertical: true)
            ForEach(model.feeds) { feed in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(feed.name).font(.system(size: 12, weight: .semibold))
                        Spacer()
                        Button("Cambiar enlace") { replacing = feed.id; name = feed.name }.disabled(model.calendarBusy)
                        Button("Desconectar") { model.removeCalendar(feed.id) }.disabled(model.calendarBusy)
                    }
                    if let time = feed.lastUpdated { Text("Última consulta: \(time.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 10)).foregroundStyle(ArcanineTheme.muted) }
                }
            }
            if !model.feeds.isEmpty { Button("Actualizar ahora") { model.refreshCalendar(force: true) }.disabled(model.calendarBusy) }
            DisclosureGroup("Dónde encuentro mi enlace") {
                Text("En Google Calendar desde un ordenador: Configuración → elige tu calendario → Integrar el calendario → Dirección secreta en formato iCal. Si tu cuenta del trabajo no muestra esa dirección, consulta con tu administrador.")
                    .font(.system(size: 11)).foregroundStyle(ArcanineTheme.muted)
                Button("Abrir instrucciones de Google") { model.openCalendarHelp() }
            }
            Text("El enlace se guarda en el Llavero de este Mac. No lo publiques ni lo compartas: permite leer el calendario. Esta conexión solo consulta reuniones; no modifica Google.")
                .font(.system(size: 10)).foregroundStyle(ArcanineTheme.muted)
        }.padding(16).background(ArcanineTheme.card).clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ArcanineTheme.line, lineWidth: 1))
    }
}

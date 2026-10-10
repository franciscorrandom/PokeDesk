# Privacidad

PokéDesk consulta directamente a Google mediante HTTPS con la dirección iCal que cada persona configura. Solo se aceptan enlaces iCal de `calendar.google.com` y `www.google.com`; las redirecciones se limitan a esos mismos destinos válidos. No se necesita iniciar sesión con Google dentro de la app ni conceder acceso a Google Tasks.

El enlace secreto se conserva en el Llavero de macOS con el servicio `io.github.franciscorrandom.arcanine.ical.links`. El archivo de ajustes solo contiene un identificador aleatorio, el nombre del calendario y su última consulta. El contenido iCal y los validadores HTTP se conservan en memoria, sin caché HTTP persistente ni cookies. Al desconectar se elimina el enlace correspondiente del Llavero. No se incluyen enlaces privados, tokens OAuth, datos de usuario ni certificados en la descarga o el repositorio.

Las tareas, notas, sus versiones, timers y preferencias se guardan localmente en `~/Library/Application Support/Arcanine-iCal/estado.json`, con permisos de lectura y escritura para el usuario. El archivo no está cifrado por la app; conserva las protecciones normales de la cuenta y del disco de tu Mac. Las copias de seguridad de tu Mac pueden incluirlo.

PokéDesk no incorpora analítica ni envía tus notas o tareas a un servidor. Reproducir una voz usa archivos incluidos. Los botones de ayuda abren páginas oficiales de Google o Apple en tu navegador. El botón de ingreso a una reunión abre el enlace del proveedor en tu navegador, con sus políticas de privacidad correspondientes.

No compartas la dirección secreta de iCal. Si la expones, renuévala en Google Calendar y actualízala en PokéDesk. Si una consulta falla se conserva la última agenda en memoria y se muestra el error; tras reiniciar la app es necesaria una nueva consulta para mostrar reuniones.

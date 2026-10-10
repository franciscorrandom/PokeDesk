# Arcanine · compañero de escritorio para Mac

Mascota 3D flotante con Arcanine y Mewtwo, animaciones articuladas, agenda de Google Calendar por iCal, tareas locales, notas con historial y timers de concentración. Aplicación nativa de macOS: Swift, AppKit, SwiftUI y SceneKit. No necesita Google Cloud, JSON OAuth ni servicios de pago para funcionar.

## Instalar

Requiere **macOS 14 Sonoma o posterior**, en Mac Intel o Apple Silicon. La descarga es universal e incluye todos los recursos; no hay que instalar herramientas de programación.

1. Descarga `Arcanine-1.2.0-macOS.zip` desde [Releases](https://github.com/franciscorrandom/arcanine-desktop-ical/releases).
2. Descomprime el ZIP y arrastra `Arcanine.app` a Aplicaciones.
3. Abre la app. Esta edición gratuita está firmada de forma local, **sin Developer ID ni notarización**. Si macOS bloquea la apertura, después de intentarla ve a **Ajustes del Sistema → Privacidad y seguridad → Abrir igualmente** y confirma. Sigue las [instrucciones de Apple](https://support.apple.com/es-cl/102445); no hace falta desactivar la seguridad del Mac.
4. En la bienvenida pega tu enlace iCal de Google Calendar y pulsa **Conectar calendario**. Puedes usar tareas, notas, animaciones y concentración aunque no conectes un calendario.

La cuenta gratuita de Apple Developer no incluye Developer ID. Para distribuir una futura versión notarizada se necesita una membresía del Apple Developer Program y el certificado correspondiente. [Información de Apple](https://developer.apple.com/developer-id/).

## Conectar Google Calendar

En un ordenador, abre Google Calendar y entra en **Configuración → Configuración de mis calendarios → tu calendario → Integrar el calendario → Dirección secreta en formato iCal**. Copia ese enlace y pégalo únicamente dentro de Arcanine. El nombre del calendario es opcional. Puedes añadir varios calendarios.

El enlace permite leer el calendario y se guarda en el **Llavero de macOS**. No lo publiques en GitHub, mensajes ni capturas. Si lo expones, cambia la dirección secreta desde Google. Algunas organizaciones deshabilitan esa opción; en ese caso consulta con tu administrador. [Instrucciones de Google](https://support.google.com/calendar/answer/37648?hl=es).

Arcanine consulta los próximos siete días y vuelve a consultar cada cinco minutos. Puedes pulsar **Actualizar ahora**. Los cambios dependen de cuándo Google los incluya en el feed iCal: no es una conexión instantánea. Se admiten repeticiones, excepciones, cancelaciones y zonas horarias. Los eventos de todo el día aparecen en la agenda y no generan avisos de reunión.

La conexión es de lectura: crea o cambia reuniones desde Google Calendar. Las tareas de Arcanine son propias de la app; no se conectan con Google Tasks.

## Usar la mascota

- **Clic:** menú semicircular con Acariciar, Agenda, Concentración, Animaciones, Notas y Abrir.
- **Arrastrar:** mover a otra parte del escritorio.
- **⌥ Option + arrastrar:** rotación horizontal para ver otros perfiles.
- **⇧ Mayús + arrastrar:** acariciar; también puedes elegir Acariciar en el menú.
- **Compañero:** elige Arcanine o Mewtwo en Ajustes → Tu compañero. El menú, los avisos y el timer adoptan sus colores. Se conservan agenda, tareas, notas y orientación de cada personaje.
- **Pokébolas 3D:** al abrir la app, una Pokébola se abre y materializa al compañero con luz blanca y azul. Al cambiar de personaje, otra lo recoge con luz rosada antes de liberar al nuevo. Tapa articulada, halo, haz y destellos sobre fondo transparente. Se omite cuando desactivas el movimiento o macOS tiene activado Reducir movimiento.
- **Animaciones:** once gestos de Arcanine y nueve de Mewtwo, incluidos parpadeos, saludo, caricias, movimiento de cola y meditación.
- **Agenda:** avisos anticipados configurables y botón para entrar cuando el evento contiene un enlace compatible de Google Meet, Zoom, Teams o Webex.
- **Tareas:** crear recordatorios, completar o eliminar; se pueden repetir cada día o solo entre semana.
- **Notas:** texto, categoría opcional, búsqueda, ediciones con historial y archivo reversible.
- **Concentración:** timers, pausa y reanudación. El indicador flotante desaparece al terminar.
- **Ajustes:** tamaño, movimiento, sonidos, Gracie/Holden e inicio al iniciar sesión. La barra de menús permite pausar avisos y salir.

Los avisos hablados de reuniones son grabaciones genéricas en inglés, disponibles con Gracie y Holden; los títulos y detalles aparecen en pantalla. No se sintetizan nombres ni títulos de reuniones. Timers y tareas utilizan un sonido. No se hacen llamadas a Higgsfield ni a servicios de voz al usar la app.

Para recibir avisos Arcanine debe estar abierto. La app puede configurarse para iniciar al iniciar sesión; un Mac dormido o apagado no puede mostrar avisos.

## Datos y privacidad

Tareas, notas, ajustes y timers se guardan en `~/Library/Application Support/Arcanine-iCal/estado.json`. Los enlaces privados se guardan aparte en el Llavero. La agenda descargada permanece en memoria durante la sesión. No hay servidor de Arcanine, analítica, cuenta propia ni sincronización de notas o tareas entre dispositivos. Consulta [Privacidad](docs/PRIVACIDAD.md).

Esta edición usa un identificador y un perfil separados de la versión anterior de Miga/Arcanine: no importa tus datos personales ni tu conexión OAuth. Para evitar dos mascotas a la vez, cierra la anterior antes de abrir esta.

## Compilar y verificar

Esta edición con iCal es la base del producto para futuras mejoras. El selector de mascotas y las animaciones de Mewtwo se documentan en [Personajes](docs/PERSONAJES.md).

Necesitas un Mac con herramientas de desarrollo de Apple y Swift 5.9 o posterior. Desde la carpeta del proyecto:

```bash
./scripts/test.sh
./scripts/build-macos.sh
```

El primer build descarga GLTFKit2 desde su repositorio oficial, fijado a un commit. Genera `dist/Arcanine.app` y `dist/Arcanine-1.2.0-macOS.zip`, firmados localmente. No se requiere Node para ejecutar ni compilar: ICAL.js está incluido y funciona dentro de JavaScriptCore.

Para compilar solo una arquitectura: `ARCANINE_ARCHS=arm64 ./scripts/build-macos.sh`. Para usar un certificado ya instalado: `ARCANINE_SIGN_IDENTITY='Developer ID Application: …' ./scripts/build-macos.sh`. Consulta [Distribución](docs/DISTRIBUCION.md) para notarizar una futura versión.

Las pruebas cubren avisos, timers, datos persistentes, notas, movimiento, secuencias de aparición y retirada, fechas iCal, recurrencias, cancelaciones, cambios de hora y respuestas HTTP con un servidor simulado. No acceden a calendarios reales ni al Llavero personal. El binario acepta `--smoke-test`, `--characters-smoke-test` y `--pokeball-smoke-test` para pruebas visuales automáticas con perfiles temporales. Para regenerar únicamente la biblioteca de Mewtwo se usa `python3 scripts/animate-mewtwo.py` con NumPy; esto no se necesita para compilar ni ejecutar la app.

## Créditos

Proyecto de fans independiente, sin afiliación con Pokémon, Nintendo, Game Freak ni Creatures. El código propio está disponible bajo MIT; los recursos de terceros mantienen sus licencias y derechos respectivos. Véase [Créditos y licencias](docs/CREDITOS.md).

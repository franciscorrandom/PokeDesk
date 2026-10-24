# PokéDesk para Windows · 1.5.0-beta.1

Primera edición Windows del producto con iCal. Electron y Three.js utilizan los mismos seis modelos, miniaturas, grabaciones y bibliotecas de animación de la edición Mac. No utiliza el cliente OAuth ni Google Tasks del prototipo anterior de Arcanine.

## Instalar y usar

Edición x64 para Windows 10/11 con controladores gráficos compatibles con WebGL 2. Ejecutar el instalador `PokeDesk-1.5.0-beta.1-Windows-x64.exe`; instala para el usuario actual y permite elegir la carpeta. Como alternativa, extraer **todo** el ZIP y abrir `PokeDesk.exe` dentro de la carpeta. No requiere Node, Python ni herramientas de desarrollo para utilizarla. El instalador todavía no lleva firma digital.

Cerrar la antigua app Arcanine desde la bandeja antes de abrir PokéDesk. Esta edición usa un perfil propio y no importa la conexión OAuth ni los datos de la app anterior. Tampoco sincroniza datos con la edición Mac.

En Ajustes → Google Calendar por iCal, pegar la **dirección secreta en formato iCal**, que se obtiene en Google Calendar → Configuración → tu calendario → Integrar el calendario. El nombre es opcional. Se admiten hasta diez calendarios, lectura de siete días, recurrencias, excepciones, cancelaciones y zonas horarias. La actualización es cada cinco minutos, con espera creciente ante errores. No requiere Google Cloud, una cuenta de PokéDesk ni la contraseña de Google. Las demás funciones se pueden usar sin calendario.

- Clic: menú semicircular, con acceso rápido a cambiar Pokémon.
- Arrastrar: mover. Alt + arrastrar: girar horizontalmente. Mayús + arrastrar: acariciar.
- Arcanine, Mewtwo, Pikachu, Charizard, Lucario y Gengar, con sus colores, 56 clips en total y miniaturas 3D.
- Pokébola articulada, halo azul al aparecer y rojo al recoger. Se omite al desactivar movimiento o usar Reducir movimiento.
- Agenda y avisos con acceso a enlaces de Meet, Zoom, Teams o Webex.
- Tareas propias, de una vez o repetidas por días, completado y eliminación.
- Notas con categoría opcional, búsqueda, historial, archivo y restauración.
- Foco de 5/10/30 minutos o personalizado, pausa, reanudación y aviso final. El contador desaparece al terminar.
- Tamaño, movimiento, sonidos, Gracie/Holden en inglés e inicio al entrar a Windows.
- Bandeja: abrir, cambiar Pokémon, ocultar, restablecer posición, pausar avisos y salir.

La app debe estar abierta para avisar. Tras suspensión comprueba los timers y recordatorios pendientes. Los avisos de reuniones son grabaciones genéricas en inglés; timers y tareas usan un sonido. No utiliza servicios de voz ni créditos.

## Datos

`%APPDATA%\PokeDesk\estado.json`: tareas, notas, timer, avisos pospuestos y ajustes. `calendar-links.enc`: enlaces iCal cifrados mediante el almacén seguro del sistema; nunca se incluyen en los snapshots enviados al visor. Los calendarios descargados permanecen en memoria durante la sesión. No hay analítica, servidor propio ni sincronización de datos entre dispositivos. No compartir enlaces privados iCal.

## Desarrollo y compilación

Desde esta carpeta, con Node 24 y npm:

```sh
npm ci
npm test
npm run smoke
npm run build:windows
```

El paso `vendor` copia recursos públicos de `../Assets`, incluidos ICAL.js y su licencia, y las utilidades oficiales de Three.js. Las copias en `assets/` y `src/renderer/vendor/` se generan; la fuente de modelos y animaciones se mantiene única para Mac y Windows. Para explorar sin datos reales: `npm start -- --demo`.

La prueba `smoke` usa un perfil ficticio separado. Comprueba los seis modelos, clips, transparencia, perfiles en 360 grados, anclaje de menú/timer, clics repetidos, escalas, memoria GPU al cambiar y datos locales. Guarda resultados y capturas en `.build/`. La compilación de vista previa en Mac sirve para comprobar empaquetado; no sustituye a la prueba nativa de Windows. GitHub Actions ejecuta las pruebas y genera artefactos en Windows mediante `.github/workflows/windows.yml`.

## Rendimiento y verificación

Un único visor WebGL, límite de 30 frames/s y resolución de dibujo limitada a 1,5 veces el tamaño lógico. La máscara para clics se lee a baja resolución cuatro veces por segundo. Se liberan texturas, geometrías, esqueletos y acciones del personaje saliente. Las vistas de controles cargan sin Three.js y comparten un solo panel. Sin movimiento, el visor dibuja únicamente cuando cambia algo; ocultarlo detiene su renderizado. El lector iCal corre en un worker con límites de tamaño, tiempo y memoria para no bloquear los clics ni las animaciones.

El menú y el timer pertenecen a la misma ventana que la mascota y se anclan a su silueta visible. La interacción usa DIP para monitores con escala distinta, mantiene captura durante los gestos y la libera ante cancelación, pérdida de captura, suspensión o cambio de pantalla. Las zonas transparentes dejan pasar los clics al escritorio.

La beta debe probarse en un equipo Windows real con su GPU y escalado, antes de habilitarla como descarga estable en el sitio. Las pruebas automáticas no garantizan ausencia de fallos en todos los controladores gráficos. Resultados de la comprobación local: [Verificación](docs/VERIFICACION.md).

## Créditos

Código propio MIT. Proyecto de fans independiente. Los recursos mantienen sus derechos y licencias: [créditos completos](../docs/CREDITOS.md). ICAL.js MPL 2.0; Three.js MIT; Electron MIT. Las atribuciones se incluyen en el paquete.

## Órbita y calendarios grandes

El menú aparece desde el centro del compañero; sus áreas de clic se actualizan durante la microinteracción. El movimiento reducido elimina las animaciones del menú. El panel usa superficies claras y una paleta por Pokémon, y permite cambiar directamente de compañero. El lector iCal admite hasta 50 MB y mantiene la conexión y los últimos eventos si falla una actualización. Los calendarios grandes se procesan de uno en uno, en un worker separado.

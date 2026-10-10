# Personajes y evolución del producto

La edición nativa para Mac con iCal (`arcanine-ical`) es la base del producto que se seguirá mejorando. Su repositorio es https://github.com/franciscorrandom/arcanine-desktop-ical. Las versiones anteriores con OAuth y la adaptación anterior de Windows son referencias separadas.

## Preparación del selector

- El selector se encuentra en Ajustes → Tu compañero.
- `PetCharacter` define el recurso GLB, nombre, número, tipo, títulos y gestos compatibles de cada personaje.
- El perfil conserva agenda, tareas, notas, voz, avisos enviados y timer al cambiar de mascota. Los campos nuevos son opcionales; los perfiles de la versión 1.0.1 conservan Arcanine.
- Se guarda una orientación horizontal por personaje. La orientación anterior de Arcanine se mantiene.
- El visor reemplaza la escena solo después de validar el modelo y sus clips. Las cargas antiguas se descartan al cambiar rápidamente de elección; ante un error se conserva la mascota anterior.
- La app incluye los recursos completos, de modo que sus usuarios no necesitan Sketchfab ni herramientas de desarrollo. El acceso a Sketchfab es únicamente parte de la preparación del nuevo recurso.

## Mewtwo incluido

El modelo se descargó mediante el botón oficial de Sketchfab el 10 de octubre de 2026: [Mewtwo de nguyenlouis32](https://sketchfab.com/3d-models/mewtwo-f6ef9b83b4744706a24cf7c5eb4d689e), CC BY 4.0. Es el mismo autor del Arcanine de la app. Tiene 77 articulaciones y no traía animaciones.

Se conserva el GLB original en `Models/Mewtwo/mewtwo-original.glb`. `scripts/animate-mewtwo.py` genera `Assets/mewtwo-biblioteca.glb`: prepara una postura relajada con cola curvada, reconstruye los enlaces del esqueleto, reutiliza el atlas original para los parpadeos y añade nueve clips articulados. NumPy se usa solo para regenerar el recurso durante el desarrollo. El catálogo está en `Models/Mewtwo/catalogo.json`.

Los gestos son levitación y parpadeo, mirada curiosa, saludo con la mano, cola en movimiento, estiramiento, aviso psíquico, celebración, caricias y meditación. Se comparten los identificadores de las acciones para mantener los avisos y timers; los títulos y movimientos son propios de Mewtwo. Reducir movimiento mantiene una postura estática y permite girar manualmente.

Arcanine usa rojo y crema; Mewtwo usa violeta y lavanda. Una paleta común se aplica al panel completo, los accesos semicirculares, sus detalles, los avisos y el indicador de foco.

La versión 1.1.0 incluye ambos modelos completos. El cambio se verifica en el visor nativo, incluyendo retorno a Arcanine, conservación de notas/tareas/timer, persistencia, rotación horizontal y los nueve clips. Los usuarios no necesitan cuenta de Sketchfab ni descargar modelos adicionales.

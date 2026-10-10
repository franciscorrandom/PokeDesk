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

## Aparición y retirada con Pokébola (1.2.0)

La Pokébola se genera con geometría de SceneKit: dos semiesferas, revestimiento, bisagra, borde y botón. No requiere descargar un modelo adicional. El brillo combina material emisivo temporal sobre el Pokémon, luz puntual, halos con alfa gradual, un haz y destellos. La composición mantiene el fondo transparente del panel nativo.

Al iniciar se reproduce la aparición (2,35 segundos). Al cambiar se valida primero el modelo entrante, se recoge el compañero actual (1,85 segundos) y se libera al siguiente. Las dos Pokébolas aparecen en posiciones distintas y su orientación es independiente de la rotación guardada del personaje. Una línea de tiempo única permite reproducción por reloj y capturas deterministas.

Al terminar o cancelar se restauran tamaño, posición, opacidad y emisión originales; la geometría del efecto se elimina. La selección rápida descarta cargas y completaciones obsoletas. Desactivar movimiento o activar Reducir movimiento finaliza cualquier transición y muestra el compañero directamente. Se conservan tareas, notas y timers durante la secuencia. La opción de girar espera a que termine la transición; el arrastre normal sigue moviendo el panel.

## PokéDesk 1.3.0: cuatro compañeros

Pikachu y Charizard se descargaron desde el botón oficial de Sketchfab el 10 de octubre de 2026. Los originales, autores y licencias están en `Models/Pikachu` y `Models/Charizard` y en [Créditos](CREDITOS.md). No requieren descargas adicionales ni cuenta de Sketchfab para el usuario final.

El generador `scripts/animate-companions.py` conserva los rigs originales (49 y 87 huesos), hornea una postura compacta con normales e inverse binds coherentes y genera nueve clips de 30 fps: reposo, curiosidad, saludo, cola, estiramiento, aviso, celebración, caricias y descanso. Pikachu mueve sus orejas; Charizard articula las alas y la llama. Los parpadeos usan los atlas originales, adheridos al hueso de la cabeza. Los clips cierran en la postura de reposo con curvas de entrada y salida suaves.

Los colores son rojo/crema para Arcanine, violeta/lavanda para Mewtwo, ámbar/amarillo para Pikachu y azul verdoso/naranja para Charizard. La paleta se aplica al menú, los paneles, los avisos y el timer.

El menú conserva seis accesos en el arco y añade una cápsula central **Cambiar Pokémon**, que abre una cuadrícula de cuatro miniaturas. También hay un selector en la barra de menús. Agenda, notas, tareas, voz y timer se conservan; cada personaje recuerda su orientación. El nombre PokéDesk mantiene el identificador y el perfil anterior para conservar la configuración.

La Pokébola espera a la preparación de los recursos de SceneKit antes de comenzar su reloj. Reabrir la app o mostrar la mascota repite su salida; también existe un botón manual. Las cargas canceladas no pueden iniciar efectos pendientes. Se respeta Reducir movimiento.

`--roster-smoke-test` usa un perfil aislado y comprueba los dos modelos nuevos, nueve clips, parpadeos, ocho orientaciones en tres instantes por clip, conservación de datos, reapertura con Pokébola y selector rápido. `--pokeball-smoke-test` comprueba arranque real, retirada/salida y cambios rápidos o cancelados.

## Correcciones visuales de 1.3.1

El halo azul de salida y rojo de retirada usa una corona saturada con mezcla alfa, un centro blanco y un haz luminoso. La mezcla aditiva por sí sola desaparecía sobre escritorios blancos. La sustitución de la malla, la ocultación inicial y el primer fotograma de salida se publican en una sola transacción de SceneKit; durante la preparación de la GPU, la nueva mascota permanece oculta.

Charizard conserva sus texturas originales de máscara: el fragment shader convierte la máscara en transparencia y color de fuego premultiplicado, sin rectángulos negros. Se amplía su límite de escala horizontal de 3,8 a 4,6 unidades, manteniendo el encuadre verificable al girarlo. Pikachu baja toda la cadena de cada brazo desde los hombros; se reconstruyen la geometría, normales e inverse binds y los gestos parten de esa postura de descanso.

Las cuatro miniaturas son capturas estáticas de los modelos de la app, con la misma cámara, iluminación y encuadre de 320 × 320 píxeles. Se cargan explícitamente desde el bundle. Para regenerarlas, ejecuta el binario con `--thumbnail-test` y después `python3 scripts/make-thumbnails.py` (Pillow, solo durante el desarrollo).

Las pruebas incluyen contraste rojo/azul sobre fondo blanco, preparación gráfica demorada sin aparición anticipada, manos de Pikachu por debajo de los hombros, presencia de las cuatro miniaturas y encuadre de los nueve gestos de Pikachu/Charizard desde ocho perfiles.

## Postura natural de Pikachu (1.3.2)

El hombro mantiene su unión anterior con el pecho. El brazo se baja desde su propia articulación y el codo se dobla ligeramente hacia dentro, dejando las manos delante del abdomen. Esto evita que la rotación de toda la cadena desde el hombro deforme la salida del brazo. La cabeza se inclina 9,7 grados hacia delante junto con los ojos y las orejas. Se reconstruyen la malla y sus enlaces antes de generar los nueve gestos.

La miniatura se actualiza desde el visor nativo. El modo `--thumbnail-test` captura además frente y perfil de Pikachu para revisar la postura; `--roster-smoke-test` comprueba sus nueve clips desde ocho orientaciones en tres instantes por clip.

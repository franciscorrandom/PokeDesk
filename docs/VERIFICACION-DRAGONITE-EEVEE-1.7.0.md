# Dragonite y Eevee · PokéDesk 1.7.0 de prueba local

Fecha: 17 de noviembre de 2026, America/Santiago.

Se incorporan Dragonite y Eevee como octavo y noveno compañeros, conservando
Bulbasaur y los seis anteriores. Cada nuevo personaje incluye nueve gestos,
miniatura del visor nativo, paleta propia y orientación guardada. El selector
compacto muestra tres filas de tres opciones. Los IDs y el perfil de datos
conservan calendario iCal, tareas, notas, voz y temporizador.

## Recursos

Dragonite conserva 80 articulaciones, 5699 triángulos y párpados articulados.
Se decodifican Draco/WebP a geometría flotante y PNG embebidos, se adaptan los
movimientos originales y se hornea la postura de pie en geometría y matrices
inversas para centrar el modelo y encuadrar su cola al girar.

Eevee conserva 69 articulaciones y 5010 triángulos. Sus nueve gestos incluyen
orejas, cola, saludo con una pata, caricias y descanso. El parpadeo usa el atlas
original; los apoyos se resuelven durante la preparación de los clips.

Originales, licencias CC BY 4.0, procedencia fijada, hashes y generadores
reproducibles están en Models/Dragonite, Models/Eevee y scripts/prepare-*.
No se ejecutan herramientas de autoría ni servicios externos al usar la app.

## Verificación

- bash scripts/test.sh: correcto, incluidos los modelos anteriores, migración,
  notas, iCal, movimiento, timers y Pokébolas. Los nuevos GLB verifican pesos,
  texturas portables, parpadeo, nueve clips distintos con extremos cerrados y
  cuaterniones continuos. Paso máximo: Dragonite 22,03° y Eevee 5,48° por clave.
- Paquete Mac universal arm64 + x86_64, macOS 14 o posterior. Firma local y
  codesign --verify --deep --strict correctos.
- --roster-smoke-test del paquete final: todos los booleanos verdaderos; nueve
  modelos y nueve miniaturas incluidos; los ocho compañeros adicionales pasan
  sus gestos, parpadeo, articulaciones, giros y transiciones. Ninguna muestra
  recortada. Datos conservados y selector completo visible.
- El test de parpadeo fuerza un render antes de leer las poses de SceneKit;
  Dragonite se verifica contra la posición real de sus párpados y Eevee contra
  la expresión del atlas, sin marcadores ficticios.
- npm test: 32 pruebas correctas. Visor Electron ejecutado en Mac: nueve modelos,
  83 clips, 4980 muestras de orientación/fase sin recortes, nueve opciones del
  selector visibles, 300 ciclos de interacción y cero errores registrados.

La ejecución Electron sobre Mac no sustituye una validación nativa en Windows.
No se generó un nuevo instalador Windows. Esta entrega es local; no publica
Releases ni actualiza las descargas de GuíaEstudio.

Informes: dist/roster-smoke-test.json y windows/.build/smoke-results.json.
Capturas nativas en dist; vista conjunta: dist/dragonite-eevee.png.

# Dragonite

El original se conserva intacto en `dragonite-original.glb`.

- Fuente del modelo y licencia verificada: https://sketchfab.com/3d-models/dragonite-official-874c7fcdbd344c7bb9e8ed3e6a04dfac
- Publicado por Mariokart07: https://sketchfab.com/Mariokart07
- La descripción del autor atribuye modelo, texturas (excepto ojos) y animaciones a GAME FREAK.
- Licencia publicada y embebida: CC BY 4.0, https://creativecommons.org/licenses/by/4.0/.
- Copia pública redistribuida, fijada a una revisión: https://raw.githubusercontent.com/Pokemon-3D-api/assets/429de1288cea0d43f5b4f56305d2276e94239d65/models/opt/regular/149.glb
- Índice de procedencia y atribución: https://github.com/huanghdm88/pokemon-3d-models/blob/main/models-manifest.json
- Descargado el 17 de noviembre de 2026. GLB 2.0, 5 675 848 bytes.
- SHA-256: `becaa8098e26676837dd2f19589a16c774e46b433118b9d911cc7876abbe36b8`.
- 80 articulaciones, cuatro mallas necesarias (dos partes del cuerpo y los ojos), 62 animaciones originales y tres texturas embebidas.

`Assets/dragonite-biblioteca.glb` conserva geometría, pesos, rig y texturas, con
Draco descodificado, atributos flotantes y PNG embebidos para SceneKit y Three.js.
Los nueve gestos se preparan desde las animaciones originales, interpolados a
30 Hz, con entrada y salida suaves hacia la misma postura de reposo. El saludo
utiliza el brazo derecho; la cola añade movimiento articular encadenado. Los
párpados originales se deforman mediante sus huesos: no hay mallas ficticias
para simular o verificar expresiones. El cierre de ojos de reposo está en t=3 s
y sus poses de referencia aparecen en `asset.extras.pokedeskBlink` y el catálogo.
La postura de pie se hornea en vértices y normales y se reconstruyen las
matrices inversas del rig, para que el encuadre use la silueta real de reposo.

Regeneración (solo herramientas de desarrollo, no necesarias para la app):

```sh
npm install --prefix .build/gltf-tools @gltf-transform/core@4.3.0 @gltf-transform/extensions@4.3.0 @gltf-transform/functions@4.3.0 draco3dgltf@1.5.9 sharp@0.35.5
python3 -m venv .build/authoring
.build/authoring/bin/pip install numpy
node scripts/prepare-dragonite.cjs
```

También se puede indicar una instalación existente mediante
`POKEDESK_GLTF_TOOLS=/ruta/al/directorio node scripts/prepare-dragonite.cjs`.
`POKEDESK_PYTHON` permite indicar otro intérprete con NumPy instalado.
`catalogo.json` documenta clips, fuentes y modificaciones; `inspeccion-original.json`
registra el contenido del archivo original.

Pokémon y sus personajes conservan los derechos de sus titulares. Este recurso
no queda cubierto por la licencia MIT del código de PokéDesk.

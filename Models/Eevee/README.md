# Eevee · referencia de nguyenlouis32

Modelo exacto de la referencia indicada por el usuario, recuperado del corpus
público Objaverse el 17 de noviembre de 2026. Se conserva intacto.

- Autor y licencia embebidos: nguyenlouis32 (https://sketchfab.com/nguyenlouis32), CC BY 4.0 (https://creativecommons.org/licenses/by/4.0/).
- Fuente original: https://sketchfab.com/3d-models/eevee-e93d3b389ea04c9ca8e532b7471a1cb0
- Descarga pública: https://huggingface.co/datasets/allenai/objaverse/resolve/main/glbs/000-016/e93d3b389ea04c9ca8e532b7471a1cb0.glb
- Índice de procedencia: https://huggingface.co/datasets/allenai/objaverse/resolve/main/object-paths.json.gz
- Archivo `eevee-original.glb`: 364476 bytes.
- SHA-256: `e556fd1be296ca85e3cef875c905e23695ea59eccbfa073574cfc08f9e9ecbeb`.
- 57 articulaciones, tres mallas, tres texturas PNG embebidas y ninguna animación fuente.

Se conservan la pose natural erguida, los colores, la geometría del cuerpo,
los pesos y las matrices de enlace originales. Los ojos siguen la cabeza y
cambian entre las tres expresiones reales del atlas original. La biblioteca
añade nueve gestos, con apoyos de patas resueltos y horneados a 30 Hz, orejas,
cola, saludo, celebración con pasos alternados, caricias y descanso.
No se modifican las imágenes del modelo.

Regenerar desde la raíz del proyecto:

```sh
node scripts/prepare-eevee.mjs
python3 scripts/prepare-eevee.py
```

El paso Node valida el hash y copia el recurso intacto, sin dependencias
adicionales. Python requiere NumPy únicamente para preparar las animaciones.
No hay decodificadores ni servicios durante la ejecución de la app.

El Eevee alternativo de la prueba 1.7.0 se conserva en
`.build/backup-eevee-1.7.0/` para permitir recuperar aquella prueba.
Pokémon y sus personajes conservan sus derechos respectivos. Este recurso
no está cubierto por la licencia MIT del código de PokéDesk.

# Eevee de referencia · PokéDesk 1.7.1 de prueba local

Fecha: 17 de noviembre de 2026, America/Santiago.

Eevee se sustituye por el modelo exacto de nguyenlouis32 que indicó el usuario,
UID e93d3b389ea04c9ca8e532b7471a1cb0. El archivo original se obtiene del corpus
público Objaverse; sus metadatos confirman autor, licencia CC BY 4.0 y el enlace
exacto de Sketchfab. SHA-256 del original conservado: e556fd1be296ca85e3cef875c905e23695ea59eccbfa073574cfc08f9e9ecbeb.

Se preservan la postura erguida, el café claro, las tres texturas PNG originales,
la geometría del cuerpo, los pesos y las matrices de enlace. Las dos patas
delanteras se extienden visibles por debajo del pecho y los ojos miran al frente.
No se recolorean las imágenes ni se cambia la cámara para esconder la postura.
El modelo tiene 57 articulaciones y 5094 triángulos activos en la biblioteca.
Se añaden nueve gestos con parpadeo desde el atlas original, orejas, cola,
saludo con una pata, caricias y descanso. Los apoyos se resuelven al preparar
los clips y no requieren IK en la aplicación.

## Verificación

- bash scripts/test.sh pasó completo. Tests/new-companions.py usa solo stdlib
  y comprueba mirada frontal, altura de cabeza y cuello, extensión visible de
  ambas patas delanteras, parpadeo, continuidad, pesos, longitudes y apoyos.
  Error de contacto menor que 0,000001 m; paso máximo por clave de 7,26°.
- El helper scripts/preview-companion.swift verifica frente, perfil y tres
  cuartos con la cámara y luz del visor nativo, sin usar perfiles reales.
- Paquete Mac universal arm64 + x86_64, macOS 14 o posterior, firmado localmente.
- --roster-smoke-test del paquete final: todos los booleanos verdaderos, ninguna
  muestra recortada, nueve modelos/miniaturas y selector completo visibles.
  Eevee pasa sus nueve gestos, parpadeo, 57 articulaciones, giros y Pokébolas;
  notas, tareas y temporizador se conservan al cambiar de compañero.
- npm test: 32 pruebas correctas. Visor Electron en Mac: nueve modelos, 83 clips,
  4980 muestras de orientación/fase sin recortes, 300 ciclos de interacción y
  cero errores. Eevee aporta 540 muestras y un margen mínimo de 38,7 px.
- El GLB de Dragonite mantiene exactamente el hash de la entrega 1.7.0. Sus
  movimientos provenían del modelo y se adaptaron a duraciones y transiciones
  de PokéDesk. Esta revisión no modifica su modelo ni sus animaciones.

La prueba Electron se ejecuta en Mac; no es validación nativa de Windows.
No se genera un nuevo instalador Windows ni se publican Releases o cambios web.
La aplicación mantiene su identificador y perfil anterior. Prueba 1.7.0 y
respaldo del modelo anterior disponibles localmente.

Informes: dist/1.7.1/roster-smoke-test.json y windows/.build/smoke-results.json.
Comparación visual nativa: dist/1.7.1/eevee-corregido.png.

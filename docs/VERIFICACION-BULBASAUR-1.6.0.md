# Bulbasaur · PokéDesk 1.6.0 en preparación

Fecha: 29 de octubre de 2026. Entrega local; sin publicar en Releases ni modificar GuíaEstudio.

Bulbasaur se integra como séptimo compañero con 72 articulaciones originales,
nueve clips y miniatura capturada del mismo renderizador. El modelo preparado
ocupa 973.780 bytes y conserva las texturas embebidas. El autor es nguyenlouis32,
CC BY 4.0; original, fuente, hash y cambios están en `Models/Bulbasaur/`.

Los gestos incluyen parpadeo, curiosidad, saludo con una pata delantera,
movimiento del bulbo, estiramiento, aviso atento, celebración con pasos
alternados, caricias y descanso bajo. Las lianas extendidas de ataque no se
muestran en reposo. Las patas mantienen su longitud y los apoyos se resuelven
durante la preparación del GLB. La aplicación reproduce los clips, sin ejecutar
IK ni depender de servicios adicionales.

## Validación Mac

- `bash scripts/test.sh`: pasó completo. 79 comprobaciones de núcleo, 417 de repertorios 3D, 15.867 de movimiento y distribución, 44 de iCal, 38 de notas y 1.528 de Pokébolas; validación adicional de los GLB y las siete miniaturas.
- La inspección independiente de Bulbasaur verifica longitudes constantes, ausencia de escalado de huesos, apoyos sin penetración, saludo con una sola pata y celebración alternada. El cambio articular máximo entre claves a 30 Hz es de 10,37 grados; el error de apoyo queda por debajo de 0,002 m.
- `--roster-smoke-test` del paquete final: siete modelos/miniaturas disponibles, nueve clips de Bulbasaur con movimiento, parpadeo cerrado, 72 articulaciones y sin recortes en las orientaciones muestreadas. Tareas, notas y timer se conservan al cambiar de personaje. Pokébola al reabrir y restauración del modelo verificadas.
- El selector compacto distribuye los siete compañeros en cuatro columnas y dos filas. El panel mantiene su selector y sus miniaturas. Paleta verde compartida en las superficies de Bulbasaur.
- Compilación universal `arm64` + `x86_64`, macOS 14 o posterior. Firma local y `codesign --verify --deep --strict` correctos.
- ZIP: `PokeDesk-1.6.0-macOS.zip`, 10.213.758 bytes; SHA-256 `4626a65e497946e65afe7234d9bafcc423d3a9fac4fecace873399c0e30afac6`. Modelo y miniatura del ZIP coinciden con los recursos comprobados.

## Visor compartido con Windows

El código de la edición Windows incorpora el séptimo compañero, su repertorio,
miniatura, paleta y selector. Versión en preparación: 1.6.0-beta.1.

- `npm test`: 32 pruebas correctas.
- `npm run smoke` en Electron sobre **Mac**: siete modelos, 65 clips, 3.900 muestras de orientación/fase sin recortes, transparencia e interacción de silueta correctas. Bulbasaur aporta 540 muestras y su margen mínimo es de 39 px en ese entorno.
- Menú y timer anclados, siete opciones visibles en el selector rápido, 300 ciclos de interacción, varias escalas, liberación de recursos tras catorce cambios adicionales, finalización del timer y conservación de notas/avisos correctos.
- Cero errores registrados por el visor.

Esta ejecución local **no sustituye una validación nativa en Windows**. No se
genera ni se ofrece un nuevo instalador Windows en esta entrega. Las descargas
públicas anteriores siguen vigentes hasta que se solicite publicar la revisión.

Las pruebas usan perfiles y eventos ficticios; no leen el calendario personal.
Los informes y capturas se conservan en la carpeta local de la entrega.

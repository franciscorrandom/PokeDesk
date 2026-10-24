# Lucario · original para evaluación

Descargado mediante el botón oficial de Sketchfab el 23 de octubre de 2026.

- Autor: nguyenlouis32 (https://sketchfab.com/nguyenlouis32).
- Fuente: https://sketchfab.com/3d-models/lucario-98c5d0459a434ff2ac6058be1db192b6
- Licencia publicada y embebida: CC BY 4.0, https://creativecommons.org/licenses/by/4.0/.
- Formato: GLB 2.0, 515220 bytes, con texturas embebidas.
- Esqueleto: 86 articulaciones; 7178 triángulos.
- SHA-256: `162c532042a5d8d08a2423d72277f3b60eb774b5c6bd905e0f6a1f1b9240e766`.

El original se conserva sin cambios. La estructura, los índices y los pesos de
las mallas han sido comprobados; el detalle está en `inspeccion-original.json`.
El original no incluía clips de animación. La biblioteca preparada se incluye en
`Assets/lucario-biblioteca.glb`, con nueve gestos, postura relajada y parpadeos.
Para regenerarla: `python3 scripts/animate-aura-ghost.py lucario` con NumPy.
El catálogo de cambios y clips está en `catalogo.json`; el original se conserva
sin modificar. Las miniaturas se renderizan con el visor nativo de la app.

La revisión 1.5.1 baja las cuatro prolongaciones negras detrás de la cabeza:
caen hacia abajo y atrás, con curva suave y un balanceo leve en reposo. Se
conservan sus uniones y longitudes; se reconstruyen geometría, normales e
inverse binds para que los nueve gestos partan de la postura corregida.
Referencia visual: [ilustración oficial de Lucario](https://www.pokemon.com/us/pokedex/lucario),
consultada el 24 de octubre de 2026. La referencia no se redistribuye con la app.

Pokémon y sus personajes conservan sus derechos respectivos; este recurso no
está cubierto por la licencia MIT del código de PokéDesk.

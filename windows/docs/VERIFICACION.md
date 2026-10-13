# Verificación de la beta Windows

Fecha: 12 de octubre de 2026. Host local: Mac con Apple Silicon; Electron 44.7.0, Three.js 0.186.1. Estas mediciones corresponden a la vista Electron en Mac, no a la app Swift ni a un equipo Windows.

- 25 pruebas de lógica: iCal, enlaces, recurrencias, zonas horarias, cambios de hora, cancelaciones, HTTP condicional, errores, tareas, timer, notas, guardado e interacción.
- 1.000 ciclos del controlador de gestos y 300 ciclos por IPC en la aplicación.
- 38 animaciones con transformaciones finitas y movimiento articulado.
- 2.280 perfiles: cinco fases de cada clip por doce orientaciones. Sin recortes.
- Menú y timer en la misma ventana, anclados sobre y bajo la silueta.
- Tamaños 70 %, 100 %, 125 % y 140 %; cálculos de escalado de pantalla 100/125/150/200 %, incluidos monitores con coordenadas negativas.
- Después de doce cambios adicionales: un personaje residente, una sola acción activa y recursos GPU acotados; apariencia final visible a tamaño completo, sin Pokébola residual.
- Sin movimiento, el bucle deja de dibujar continuamente. Se comprueba durante la prueba.
- Sin contactos, cuentas, calendarios reales ni envío de datos privados durante las pruebas.

La prueba de código nativa pasó en el runner Windows de GitHub Actions (run 38203264538), incluidos visor, controles y cifrado de enlaces ficticios. El workflow también verifica el ejecutable empaquetado antes de entregar los artefactos. El informe final debe distinguir su resultado del resultado local. La prueba manual pendiente debe cubrir clics/arrastres prolongados, escalado entre monitores, GPU, reanudación, autoarranque y apertura del instalador. No se ha cambiado «Windows · Próximamente» en el sitio.

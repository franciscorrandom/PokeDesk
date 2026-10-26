# Órbita · 13 de octubre de 2026

Mac 1.4.0; Windows 1.4.0-beta.2.

La interfaz usa superficies blancas, tarjetas grises, separación suave y un solo acento por Pokémon. El panel incluye cambio directo de compañero y cinco accesos principales; Ajustes sigue disponible en la cabecera. Las vistas rápidas, notas y botones utilizan la misma paleta.

Los accesos del menú nacen desde el centro del compañero con una salida escalonada de aproximadamente medio segundo. El hover amplía y eleva levemente el botón; la pulsación se comprime. Se respeta Reducir movimiento. Mac conserva el paso de clics a través del centro vacío del menú. Windows recalcula las zonas interactivas mientras los botones se mueven, cancela la animación al cerrar y no reproduce la apertura en cada actualización del reloj.

## Calendario de trabajo

El aviso anterior mezclaba dos causas: más de 10 MB y texto que no se decodificaba como UTF-8. Con una captura no se puede distinguir cuál afectó al calendario real.

Se amplió el límite a 50 MB, con lectura acotada y cancelación de respuestas superiores al límite. Se aceptan UTF-8 con BOM, UTF-16 identificado y codificaciones legacy declaradas. Las líneas plegadas que dividen un carácter UTF-8 se despliegan antes de decodificar. Una respuesta HTML o una denegación de Google produce un mensaje distinto; no se eluden las restricciones de Google Workspace. Los errores no revelan URLs privadas ni contenidos del calendario. Una actualización fallida conserva la conexión y la caché válida.

## Validación

- Suite Mac: 44 comprobaciones iCal, más las suites de timers, notas, movimiento y aparición.
- 11 MB descargados y procesados en Mac sin bloquear el hilo de la mascota.
- Suite Windows: 28 pruebas, incluyendo codificaciones, respuesta HTML, rechazo de cabeceras y cuerpos mayores a 50 MB, caché y un calendario de 11 MB.
- Prueba visual nativa de Mac: accesos pulsables, centro transparente, panel y vistas rápidas dentro de pantalla, foco, gestos, notas y cierre correctos.
- Vista Electron probada en Mac: cuatro modelos, 38 clips, 2.280 perfiles, 300 ciclos de interacción, anclaje del menú y del timer y liberación de recursos.

El calendario privado del usuario no se ha solicitado ni se ha usado en pruebas. La comprobación con su cuenta de trabajo queda para la apertura de esta versión. Las pruebas Electron en Mac no sustituyen la validación nativa del paquete Windows.

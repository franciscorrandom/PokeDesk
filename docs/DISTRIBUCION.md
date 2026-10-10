# Distribuir la app

## Edición sin membresía pagada

`scripts/build-macos.sh` produce un ZIP con una app universal para macOS 14 o posterior. La firma local permite verificar la integridad del paquete, pero no identifica a un desarrollador de confianza ante Gatekeeper y **no equivale a una notarización**. Comparte el ZIP como archivo de una Release de GitHub, junto con las instrucciones de apertura del README.

No aconsejes desactivar Gatekeeper ni quitar atributos de cuarentena. La autorización manual debe hacerse mediante la interfaz de macOS siguiendo [Apple](https://support.apple.com/es-cl/102445). Los Mac administrados por una empresa pueden impedir abrir apps no notarizadas.

El código fuente y los recursos van en el repositorio. El binario y el framework compilado solo van en las descargas de Releases, no en Git. Un ZIP de código permite reconstruir la app.

## Futura versión firmada y notarizada

La cuenta gratuita de Apple Developer permite desarrollo y pruebas, pero no incluye los certificados Developer ID. Necesitas una membresía del [Apple Developer Program](https://developer.apple.com/developer-id/), un certificado **Developer ID Application**, y credenciales de notarización guardadas de forma segura.

Con el certificado instalado, define `ARCANINE_SIGN_IDENTITY` al ejecutar el build. El script activa hardened runtime y sello de tiempo, y firma el framework antes de la app. Envía el ZIP a Apple con `xcrun notarytool submit … --keychain-profile … --wait`; únicamente después de una respuesta **Accepted**, aplica `xcrun stapler staple dist/Arcanine.app` y vuelve a generar el ZIP. Verifica con `codesign --verify --deep --strict` y `spctl --assess --type execute`.

El build local actual no ejecuta notarización ni guarda credenciales. Nunca publiques certificados `.p12`, claves, perfiles o contraseñas en el repositorio. La cuenta gratuita no impide compartir la edición actual con autorización manual de apertura.

## Automatización

El workflow de GitHub ejecuta las pruebas y genera el ZIP en un runner macOS. En un tag `v…`, crea una Release y adjunta el paquete. Las descargas automáticas tienen la misma firma local que el build por defecto. Se debe revisar el resultado del primer workflow publicado; hasta ejecutarlo no hay validación del runner remoto.

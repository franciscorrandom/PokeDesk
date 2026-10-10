#!/bin/bash
set -euo pipefail
ARCANINE_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCANINE_DIST="$ARCANINE_ROOT/dist"
ARCANINE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ARCANINE_ROOT/Info.plist")"
ARCANINE_APP="$ARCANINE_DIST/PokeDesk.app"
ARCANINE_ARCHS="${ARCANINE_ARCHS:-arm64 x86_64}"
ARCANINE_IDENTITY="${ARCANINE_SIGN_IDENTITY:--}"
ARCANINE_FRAMEWORK="${ARCANINE_FRAMEWORK:-$ARCANINE_ROOT/.build/spm/artifacts/gltfkit2/GLTFKit2/GLTFKit2.xcframework/macos-arm64_x86_64/GLTFKit2.framework}"
if [ ! -d "$ARCANINE_FRAMEWORK" ]; then
  swift build --package-path "$ARCANINE_ROOT/Dependencies" -c release --scratch-path "$ARCANINE_ROOT/.build/spm"
fi
mkdir -p "$ARCANINE_ROOT/.build/bin" "$ARCANINE_ROOT/.build/module-cache" "$ARCANINE_APP/Contents/MacOS" "$ARCANINE_APP/Contents/Frameworks" "$ARCANINE_APP/Contents/Resources"
cp "$ARCANINE_ROOT/Info.plist" "$ARCANINE_APP/Contents/Info.plist"
ditto "$ARCANINE_FRAMEWORK" "$ARCANINE_APP/Contents/Frameworks/GLTFKit2.framework"
ditto "$ARCANINE_ROOT/Assets" "$ARCANINE_APP/Contents/Resources"
cp "$ARCANINE_ROOT/README.md" "$ARCANINE_APP/Contents/Resources/LEEME.md"
cp "$ARCANINE_ROOT/LICENSE" "$ARCANINE_APP/Contents/Resources/LICENSE"
ditto "$ARCANINE_ROOT/docs" "$ARCANINE_APP/Contents/Resources/docs"
ARCANINE_BINARIES=()
for ARCANINE_ARCH in $ARCANINE_ARCHS; do
  swiftc -swift-version 5 -O -target "$ARCANINE_ARCH-apple-macos14.0" \
    -module-cache-path "$ARCANINE_ROOT/.build/module-cache" \
    -F "$(dirname "$ARCANINE_FRAMEWORK")" -framework GLTFKit2 \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    "$ARCANINE_ROOT"/Sources/*.swift -o "$ARCANINE_ROOT/.build/bin/Arcanine-$ARCANINE_ARCH"
  ARCANINE_BINARIES+=("$ARCANINE_ROOT/.build/bin/Arcanine-$ARCANINE_ARCH")
done
lipo -create "${ARCANINE_BINARIES[@]}" -output "$ARCANINE_APP/Contents/MacOS/PokeDesk"
ARCANINE_SIGN_OPTIONS=(--force --sign "$ARCANINE_IDENTITY")
if [ "$ARCANINE_IDENTITY" != "-" ]; then ARCANINE_SIGN_OPTIONS+=(--options runtime --timestamp); fi
codesign "${ARCANINE_SIGN_OPTIONS[@]}" "$ARCANINE_APP/Contents/Frameworks/GLTFKit2.framework"
codesign "${ARCANINE_SIGN_OPTIONS[@]}" --identifier io.github.franciscorrandom.arcanine.ical "$ARCANINE_APP"
codesign --verify --deep --strict "$ARCANINE_APP"
ditto -c -k --sequesterRsrc --keepParent "$ARCANINE_APP" "$ARCANINE_DIST/PokeDesk-$ARCANINE_VERSION-macOS.zip"
echo "App creada: $ARCANINE_DIST/PokeDesk-$ARCANINE_VERSION-macOS.zip"

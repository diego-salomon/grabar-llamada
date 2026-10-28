#!/bin/zsh
# Compila "Grabar Llamada.app" y la instala en /Applications.
# Se compila en una carpeta temporal para que la única copia sea la de
# /Applications (si no, Spotlight y el Launchpad la muestran dos veces).
# OJO: cada recompilación cambia la firma local y macOS olvida los permisos
# (micrófono, audio del sistema y Documentos). Habrá que darlos de nuevo.
set -e
cd "$(dirname "$0")"
TEMP=$(mktemp -d)
APP="$TEMP/Grabar Llamada.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target arm64-apple-macos15.0 *.swift -o "$APP/Contents/MacOS/GrabarLlamada"

swift herramientas/icono.swift icono.svg "$TEMP/AppIcon.iconset"
iconutil -c icns "$TEMP/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier local.grabarllamada "$APP"
rm -rf "/Applications/Grabar Llamada.app"
mv "$APP" /Applications/
echo "Instalada en /Applications/Grabar Llamada.app"

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP_DIR="$BUILD_DIR/DashboardFlow.app"
EXECUTABLE="$APP_DIR/Contents/MacOS/DashboardFlow"
MODULE_CACHE="$BUILD_DIR/module-cache"
ICON_SOURCE="$ROOT/Assets/DashboardFlowIcon.png"
ICONSET="$BUILD_DIR/DashboardFlow.iconset"
ICON_FILE="$APP_DIR/Contents/Resources/DashboardFlowIcon.icns"
ICONSET_TOOL="$BUILD_DIR/make_iconset"

echo "DashboardFlow Mac build"
echo "Projekt: $ROOT"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "Fehler: swiftc wurde nicht gefunden. Bitte installiere Xcode oder die Xcode Command Line Tools."
  echo "Tipp: xcode-select --install"
  exit 1
fi

echo "1/5 Build-Verzeichnis vorbereiten ..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$MODULE_CACHE"

echo "    Konfiguration aus .env laden ..."
ENV_FILE="$ROOT/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "    Hinweis: keine .env gefunden, verwende .env.example (Platzhalter-URL)."
  ENV_FILE="$ROOT/.env.example"
fi
# shellcheck disable=SC1090
set -a; . "$ENV_FILE"; set +a
PRODUCTION_BASE_URL="${PRODUCTION_BASE_URL:-https://dashboard.example.com}"

GENERATED_CONFIG="$ROOT/Sources/DashboardFlowMac/GeneratedConfig.swift"
cat > "$GENERATED_CONFIG" <<SWIFT
// Automatisch von build.sh aus .env erzeugt. Nicht versionieren, nicht bearbeiten.
enum AppConfig {
    static let productionBaseURL = "$PRODUCTION_BASE_URL"
}
SWIFT

echo "2/5 Swift-App kompilieren ..."
swiftc \
  "$ROOT/Sources/DashboardFlowMac/main.swift" \
  "$GENERATED_CONFIG" \
  -o "$EXECUTABLE" \
  -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  -framework SwiftUI \
  -framework WebKit \
  -framework AppKit

echo "3/5 App-Metadaten schreiben ..."
if [ -f "$ICON_SOURCE" ]; then
  echo "    App-Icon erzeugen ..."
  swiftc \
    "$ROOT/Scripts/make_iconset.swift" \
    -o "$ICONSET_TOOL" \
    -module-cache-path "$MODULE_CACHE" \
    -framework CoreGraphics \
    -framework ImageIO \
    -framework UniformTypeIdentifiers
  "$ICONSET_TOOL" "$ICON_SOURCE" "$ICONSET"
  iconutil -c icns "$ICONSET" -o "$ICON_FILE"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>de</string>
    <key>CFBundleExecutable</key>
    <string>DashboardFlow</string>
    <key>CFBundleIdentifier</key>
    <string>de.careflow.dashboardflow.mac</string>
    <key>CFBundleName</key>
    <string>DashboardFlow</string>
    <key>CFBundleDisplayName</key>
    <string>DashboardFlow</string>
    <key>CFBundleIconFile</key>
    <string>DashboardFlowIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsLocalNetworking</key>
        <true/>
    </dict>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "4/5 App lokal signieren ..."
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "5/5 Bundle prüfen ..."
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

echo
echo "Fertig:"
echo "$APP_DIR"
echo
echo "Starten mit:"
echo "open \"$APP_DIR\""

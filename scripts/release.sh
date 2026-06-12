#!/bin/bash
# Release de Sublimito: archive Release, firma Developer ID (incluida la re-firma de los
# binarios embebidos de Sparkle, que vienen firmados por el proyecto Sparkle y la
# notarización los rechaza), notarización + staple, GitHub release y appcast.
#
# Uso: scripts/release.sh "Notas de la versión"
# Requiere: perfil de keychain "sublimito-notary" (xcrun notarytool store-credentials),
# gh autenticado, y versión/build ya subidos en project.yml (el build DEBE incrementarse:
# Sparkle compara CFBundleVersion, no la versión de marketing).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="Developer ID Application: Arturo García Jurado (ZC8MCRVRBP)"
PROFILE="sublimito-notary"
REPO="arturogj92/sublimito"

VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2}' "$ROOT/project.yml")
BUILD=$(awk -F'"' '/CURRENT_PROJECT_VERSION/ {print $2}' "$ROOT/project.yml")
NOTES="${1:-Mejoras y correcciones.}"
APP="/tmp/Sublimito.app"
ZIP="/tmp/Sublimito-v$VERSION-macOS.zip"
ARCHIVE="/tmp/Sublimito.xcarchive"

echo "== Release v$VERSION (build $BUILD) =="

echo "== Archive Release =="
cd "$ROOT"
xcodegen generate
xcodebuild -project Sublimito.xcodeproj -scheme Sublimito -configuration Release \
  -archivePath "$ARCHIVE" archive -quiet

echo "== Extraer y limpiar =="
rm -rf "$APP"
cp -R "$ARCHIVE/Products/Applications/Sublimito.app" "$APP"
find "$APP" -name '.DS_Store' -delete
xattr -cr "$APP"

echo "== Firmar (de dentro hacia fuera) =="
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
for item in \
  "$SPARKLE/Versions/B/XPCServices/Downloader.xpc" \
  "$SPARKLE/Versions/B/XPCServices/Installer.xpc" \
  "$SPARKLE/Versions/B/Autoupdate" \
  "$SPARKLE/Versions/B/Updater.app" \
  "$SPARKLE"; do
  codesign --force --sign "$IDENTITY" --options runtime --timestamp "$item"
done
codesign --force --sign "$IDENTITY" --options runtime --timestamp "$APP"
codesign --verify --deep --strict "$APP"

echo "== Notarizar =="
# --norsrc: sin él, el zip lleva entradas AppleDouble (._*) que Archive Utility
# extrae como ficheros reales dentro del bundle, rompiendo el sello de la firma
# (Gatekeeper: "unsealed contents present in the root directory of an embedded framework")
/usr/bin/ditto -c -k --norsrc --keepParent "$APP" "$ZIP"
# Credenciales: fichero local (~/.config/sublimito/notary.env, fuera del repo) o,
# en su defecto, perfil del keychain (no funciona en sesiones sin GUI).
NOTARY_ENV="$HOME/.config/sublimito/notary.env"
if [ -f "$NOTARY_ENV" ]; then
  source "$NOTARY_ENV"
  xcrun notarytool submit "$ZIP" --apple-id "$APPLE_ID" --team-id "$TEAM_ID" \
    --password "$APP_PWD" --wait
else
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
fi

echo "== Staple y re-zip =="
xcrun stapler staple "$APP"
rm "$ZIP"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP" "$ZIP"

echo "== Verificación como usuario real (gate: aborta si falla) =="
# Simula la descarga de un usuario: extrae con unzip a pelo (el peor caso — materializa
# cualquier AppleDouble como fichero) y exige Gatekeeper accepted + staple válido.
VERIFY_DIR=$(mktemp -d /tmp/sublimito-verify.XXXXXX)
trap 'rm -rf "$VERIFY_DIR"' EXIT
unzip -q "$ZIP" -d "$VERIFY_DIR"
JUNK=$(find "$VERIFY_DIR/Sublimito.app" \( -name '._*' -o -name '.DS_Store' \) | wc -l | tr -d ' ')
if [ "$JUNK" != "0" ]; then
  echo "❌ ABORT: el zip contiene $JUNK ficheros AppleDouble/.DS_Store — rompería Gatekeeper" >&2
  exit 1
fi
if ! spctl -a -vv "$VERIFY_DIR/Sublimito.app" 2>&1 | tee /dev/stderr | grep -q 'accepted'; then
  echo "❌ ABORT: Gatekeeper rechaza la app extraída del zip — NO se publica" >&2
  exit 1
fi
xcrun stapler validate "$VERIFY_DIR/Sublimito.app" || { echo "❌ ABORT: ticket de notarización no grapado" >&2; exit 1; }
echo "✅ Gate OK: unzip limpio, Gatekeeper accepted, staple válido"

echo "== GitHub release =="
gh release create "v$VERSION" "$ZIP" --repo "$REPO" \
  --title "v$VERSION" --notes "$NOTES"

echo "== Verificación post-upload (lo que descargará el usuario) =="
DL_DIR=$(mktemp -d /tmp/sublimito-dl.XXXXXX)
curl -sL -o "$DL_DIR/dl.zip" "https://github.com/$REPO/releases/download/v$VERSION/Sublimito-v$VERSION-macOS.zip"
unzip -q "$DL_DIR/dl.zip" -d "$DL_DIR"
spctl -a -vv "$DL_DIR/Sublimito.app" 2>&1 | grep -q 'accepted' \
  || { echo "❌ El asset publicado NO pasa Gatekeeper — bórralo con: gh release delete v$VERSION --repo $REPO" >&2; exit 1; }
rm -rf "$DL_DIR"
echo "✅ Asset publicado verificado: Gatekeeper accepted"

echo "== Appcast =="
SIZE=$(stat -f%z "$ZIP")
cat > "$ROOT/appcast.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Sublimito Updates</title>
        <link>https://github.com/$REPO</link>
        <description>Automatic updates for Sublimito</description>
        <language>en</language>
        <item>
            <title>Version $VERSION</title>
            <description><![CDATA[
$NOTES
            ]]></description>
            <pubDate>$(date -R)</pubDate>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
                url="https://github.com/$REPO/releases/download/v$VERSION/Sublimito-v$VERSION-macOS.zip"
                sparkle:version="$BUILD"
                sparkle:shortVersionString="$VERSION"
                length="$SIZE"
                type="application/octet-stream"
            />
        </item>
    </channel>
</rss>
EOF

git add appcast.xml project.yml
git commit -m "Release v$VERSION"
git push origin master

echo "== Hecho: v$VERSION publicada =="

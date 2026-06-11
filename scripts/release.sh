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
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "== Staple y re-zip =="
xcrun stapler staple "$APP"
rm "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "== GitHub release =="
gh release create "v$VERSION" "$ZIP" --repo "$REPO" \
  --title "v$VERSION" --notes "$NOTES"

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

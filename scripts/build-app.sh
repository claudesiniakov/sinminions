#!/usr/bin/env bash
# Собирает SinMinions.app (arm64) из Swift-пакета и упаковывает в build/SinMinions.zip.
set -euo pipefail
cd "$(dirname "$0")/.."

# Версия — из последнего тега vX.Y.Z, номер сборки — число коммитов.
VERSION="${VERSION:-$( (git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true) | sed 's/^v//')}"
VERSION="${VERSION:-0.0.0}"
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
APP="build/SinMinions.app"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/SinMinions"

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SinMinions"

# Иконка: Resources/AppIcon.png (1024×1024, рисует scripts/make-icon.py) → AppIcon.icns
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SinMinions</string>
  <key>CFBundleDisplayName</key><string>SinMinions</string>
  <key>CFBundleIdentifier</key><string>com.claudesiniakov.sinminions</string>
  <key>CFBundleExecutable</key><string>SinMinions</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleDevelopmentRegion</key><string>ru</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© claudesiniakov</string>
</dict>
</plist>
PLIST

# Подпись. В CI — постоянным самоподписанным сертификатом (SIGN_IDENTITY): требование к подписи
# у всех сборок одно, и выданный «Универсальный доступ» переживает обновления.
# Без сертификата — ad-hoc: тогда после каждого обновления разрешение приходится выдавать заново.
IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --deep --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --verbose "$APP"
codesign -d -r- "$APP" 2>&1 | tee build/requirement.txt
if [ "$IDENTITY" != "-" ] && ! grep -q "certificate leaf" build/requirement.txt; then
  echo "Подпись не привязана к сертификату" >&2
  exit 1
fi
rm build/requirement.txt

ditto -c -k --keepParent "$APP" build/SinMinions.zip
# Контрольная сумма для проверки обновления внутри приложения.
(cd build && shasum -a 256 SinMinions.zip > SinMinions.zip.sha256)
echo "Готово: $APP и build/SinMinions.zip (версия $VERSION, сборка $BUILD_NUMBER)"

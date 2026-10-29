#!/bin/zsh
# Builds Chrono.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "${0:A:h}/.."

VERSION="1.0.0"
APP="build/Chrono.app"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Chrono"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Chrono"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Chrono</string>
    <key>CFBundleDisplayName</key><string>Chrono</string>
    <key>CFBundleIdentifier</key><string>me.torresrobert.chrono</string>
    <key>CFBundleExecutable</key><string>Chrono</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Torres Labs LLC. MIT License.</string>
</dict>
</plist>
EOF

codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Chrono 2>/dev/null || true
    rm -rf /Applications/Chrono.app
    cp -R "$APP" /Applications/
    open /Applications/Chrono.app
    echo "Installed and launched /Applications/Chrono.app"
fi

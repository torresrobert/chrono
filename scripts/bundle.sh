#!/bin/zsh
# Builds Vitals.app into ./build. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "${0:A:h}/.."

VERSION="1.0.0"
APP="build/Vitals.app"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Vitals"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Vitals"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Vitals</string>
    <key>CFBundleDisplayName</key><string>Vitals</string>
    <key>CFBundleIdentifier</key><string>me.torresrobert.vitals</string>
    <key>CFBundleExecutable</key><string>Vitals</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key><string>© $(date +%Y) Robert Torres</string>
</dict>
</plist>
EOF

codesign --force --sign - --timestamp=none "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x Vitals 2>/dev/null || true
    rm -rf /Applications/Vitals.app
    cp -R "$APP" /Applications/
    open /Applications/Vitals.app
    echo "Installed and launched /Applications/Vitals.app"
fi

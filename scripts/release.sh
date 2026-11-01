#!/bin/zsh
# Builds the release zip and points the Homebrew cask at it. The zip's checksum goes into
# Casks/chrono.rb, so upload this exact file as the release asset.
set -euo pipefail
cd "${0:A:h}/.."

./scripts/bundle.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Chrono.app/Contents/Info.plist)
ZIP="build/Chrono-${VERSION}.zip"

rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent build/Chrono.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

sed -i '' -e "s/^  version \".*\"/  version \"${VERSION}\"/" \
          -e "s/^  sha256 .*/  sha256 \"${SHA}\"/" Casks/chrono.rb

echo "Built $ZIP ($SHA)"
echo "Next: commit Casks/chrono.rb, then"
echo "  gh release create v${VERSION} $ZIP --title \"Chrono ${VERSION}\""

#!/bin/zsh
# Builds the release zip: signed with Developer ID, notarized and stapled. Then points the
# Homebrew cask at it, writing the zip's checksum into Casks/chrono.rb, so upload this exact file
# as the release asset.
#
# Notarization reads a notarytool keychain profile (NOTARY_PROFILE, default chrono-notary):
#   xcrun notarytool store-credentials chrono-notary --key <AuthKey.p8> --key-id <id> --issuer <id>
set -euo pipefail
cd "${0:A:h}/.."

PROFILE="${NOTARY_PROFILE:-chrono-notary}"

./scripts/bundle.sh
if ! codesign -dvv build/Chrono.app 2>&1 | grep -q "^Authority=Developer ID Application"; then
    echo "Chrono.app isn't signed with a Developer ID certificate, so it can't be notarized." >&2
    exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Chrono.app/Contents/Info.plist)
ZIP="build/Chrono-${VERSION}.zip"

# Apple notarizes the zip's contents; the ticket is then stapled to the app itself, so it opens
# without a network check, and the app is zipped again for release.
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent build/Chrono.app "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple build/Chrono.app
spctl --assess --type execute build/Chrono.app

rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent build/Chrono.app "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

sed -i '' -e "s/^  version \".*\"/  version \"${VERSION}\"/" \
          -e "s/^  sha256 .*/  sha256 \"${SHA}\"/" Casks/chrono.rb

echo "Built $ZIP ($SHA)"
echo "Next: commit Casks/chrono.rb, then"
echo "  gh release create v${VERSION} $ZIP --title \"Chrono ${VERSION}\""

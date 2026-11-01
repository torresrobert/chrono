#!/bin/zsh
# Builds the release zip: signed with Developer ID, notarized and stapled. Then points the
# Homebrew cask at it, writing the zip's checksum into Casks/chrono.rb, so upload this exact file
# as the release asset.
#
# Notarization uses an App Store Connect API key from the environment: ASC_KEY_ID, ASC_ISSUER_ID
# and ASC_PRIVATE_KEY (the .p8 file's contents), e.g. injected by a secrets manager.
set -euo pipefail
cd "${0:A:h}/.."

if [[ -z "${ASC_KEY_ID:-}" || -z "${ASC_ISSUER_ID:-}" || -z "${ASC_PRIVATE_KEY:-}" ]]; then
    echo "Set ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY to notarize." >&2
    exit 1
fi
KEY_FILE=$(mktemp -t chrono-asc)
trap 'rm -f "$KEY_FILE"' EXIT
print -r -- "$ASC_PRIVATE_KEY" > "$KEY_FILE"

./scripts/bundle.sh
if [[ "$(codesign -dvv build/Chrono.app 2>&1)" != *$'\nAuthority=Developer ID Application'* ]]; then
    echo "Chrono.app isn't signed with a Developer ID certificate, so it can't be notarized." >&2
    exit 1
fi
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/Chrono.app/Contents/Info.plist)
ZIP="build/Chrono-${VERSION}.zip"

# Apple notarizes the zip's contents; the ticket is then stapled to the app itself, so it opens
# without a network check, and the app is zipped again for release.
rm -f "$ZIP"
ditto -c -k --norsrc --noextattr --keepParent build/Chrono.app "$ZIP"
xcrun notarytool submit "$ZIP" --key "$KEY_FILE" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID" --wait
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

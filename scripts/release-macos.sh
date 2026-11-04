#!/bin/bash
# Archive Numbook (macOS) and upload it to App Store Connect / TestFlight.
#
# STATUS: the archive half is proven (unsigned, universal 0.5.2/22). The signing,
# export and upload half needs an Apple ID signed into Xcode (or an App Store
# Connect API key) plus a Team ID — it has not been run yet.
#
#   TEAM_ID=XXXXXXXXXX ./scripts/release-macos.sh
#   TEAM_ID=… ASC_KEY_PATH=… ASC_KEY_ID=… ASC_ISSUER_ID=… ./scripts/release-macos.sh
#
# Optional: VERSION=0.5.3 BUILD=23 (default: read from pubspec.yaml)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${TEAM_ID:?set TEAM_ID (developer.apple.com/account -> Membership details)}"

VERSION=${VERSION:-$(sed -n 's/^version: *\([0-9.]*\)+.*/\1/p' pubspec.yaml)}
BUILD=${BUILD:-$(sed -n 's/^version: *[0-9.]*+\([0-9]*\).*/\1/p' pubspec.yaml)}
[ -n "$VERSION" ] && [ -n "$BUILD" ] || { echo "cannot read version/build from pubspec.yaml"; exit 1; }

ARCHIVE=build/macos/Numbook.xcarchive
EXPORT=build/macos/export

echo "== archive Numbook $VERSION ($BUILD) =="
rm -rf "$ARCHIVE" "$EXPORT"
xcodebuild archive \
  -workspace macos/Runner.xcworkspace \
  -scheme Runner \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$BUILD"

echo "== export options =="
mkdir -p build/macos
cat > build/macos/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>destination</key><string>upload</string>
	<key>signingStyle</key><string>automatic</string>
	<key>teamID</key><string>$TEAM_ID</string>
	<key>uploadSymbols</key><true/>
</dict>
</plist>
PLIST

echo "== export + upload =="
if [ -n "${ASC_KEY_PATH:-}" ]; then
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist build/macos/ExportOptions.plist \
    -exportPath "$EXPORT" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$ASC_KEY_PATH" \
    -authenticationKeyID "${ASC_KEY_ID:?}" \
    -authenticationKeyIssuerID "${ASC_ISSUER_ID:?}"
else
  xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist build/macos/ExportOptions.plist \
    -exportPath "$EXPORT" \
    -allowProvisioningUpdates
fi

echo
echo "Uploaded. Next: App Store Connect -> TestFlight -> add the build to a group."
echo "The app record (bundle id app.tallynote.tallynote) must already exist in App Store Connect."

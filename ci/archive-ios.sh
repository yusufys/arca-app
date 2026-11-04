#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "${ARCA_RC_PUBLIC_KEY:-}" in
  appl_?*) ;;
  *) echo 'Set ARCA_RC_PUBLIC_KEY to the public Apple-app RevenueCat key before archiving.' >&2; exit 2 ;;
esac
archive="${ARCA_ARCHIVE_PATH:-$PWD/DerivedData/Arca.xcarchive}"
xcodebuild archive -project Arca.xcodeproj -scheme Arca -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" -allowProvisioningUpdates \
  "ARCA_RC_PUBLIC_KEY=$ARCA_RC_PUBLIC_KEY"
app="$archive/Products/Applications/Arca.app"
test "$(/usr/libexec/PlistBuddy -c 'Print :REVENUECAT_IOS_PUBLIC_KEY' "$app/Info.plist")" = "$ARCA_RC_PUBLIC_KEY"
codesign --verify --deep --strict "$app"
echo "Signed archive ready for Organizer validation: $archive"

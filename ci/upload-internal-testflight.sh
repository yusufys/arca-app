#!/bin/bash
set -euo pipefail
if [[ $# != 1 && $# != 3 ]]; then
  echo "Usage: $0 /path/to/Arca.xcarchive [ /path/to/AuthKey_KEYID.p8 issuer-uuid ]" >&2
  exit 2
fi
archive=$1
app="$archive/Products/Applications/Arca.app"
key=$(/usr/libexec/PlistBuddy -c 'Print :REVENUECAT_IOS_PUBLIC_KEY' "$app/Info.plist")
[[ $key == appl_?* ]] || { echo 'Archive requires the Apple app public key.' >&2; exit 2; }
codesign --verify --deep --strict "$app"
args=()
if [[ $# == 3 ]]; then
  path=$2
  base=$(basename "$path")
  [[ -s $path && $base =~ ^AuthKey_([A-Z0-9]+)\.p8$ ]] || { echo 'Use the downloaded App Store Connect AuthKey file.' >&2; exit 2; }
  args=(-authenticationKeyPath "$path" -authenticationKeyID "${BASH_REMATCH[1]}" -authenticationKeyIssuerID "$3")
fi
work=$(mktemp -d "${TMPDIR:-/tmp}/arca-upload.XXXXXX")
cat > "$work/export.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>teamID</key><string>KCHU685M55</string>
<key>destination</key><string>upload</string>
<key>signingStyle</key><string>automatic</string>
<key>manageAppVersionAndBuildNumber</key><false/>
<key>testFlightInternalTestingOnly</key><true/>
</dict></plist>
PLIST
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$work/export" \
  -exportOptionsPlist "$work/export.plist" -allowProvisioningUpdates ${args[@]+"${args[@]}"}

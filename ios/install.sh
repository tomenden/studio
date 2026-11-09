#!/bin/bash
# Builds the studio app and installs it on the iPhone connected by cable.
# Needed once, and again about once a year when the developer signing expires.
# Game updates never need this: the app loads the games from the website.
set -euo pipefail
cd "$(dirname "$0")"

json=$(mktemp)
xcrun devicectl list devices --json-output "$json" >/dev/null
udid=$(python3 - "$json" <<'EOF'
import json, sys
devs = json.load(open(sys.argv[1]))["result"]["devices"]
phones = [d for d in devs
          if d["hardwareProperties"].get("platform") == "iOS"
          and d["connectionProperties"].get("transportType") == "wired"]
print(phones[0]["hardwareProperties"]["udid"] if phones else "")
EOF
)
if [ -z "$udid" ]; then
  echo "No iPhone connected by cable. Connect it, unlock it, tap 'Trust', and run again."
  exit 1
fi
echo "Installing on $udid"

xcodegen generate >/dev/null
xcodebuild -project Studio.xcodeproj -scheme Studio -configuration Release \
  -destination "id=$udid" -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build -quiet
xcrun devicectl device install app --device "$udid" build/Build/Products/Release-iphoneos/Studio.app
echo "Done. On the phone: Screen Time > Always Allowed > add הסטודיו"

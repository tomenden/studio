#!/bin/bash
# Builds the studio app and installs it on Yael's iPhone: by cable, or over Wi-Fi once the
# phone has been connected by cable once (same network, phone unlocked).
# Needed again about once a year when the developer signing expires.
# Game updates never need this: the app loads the games from the website.
#
# Her phone's id comes from the git-ignored Local.xcconfig (YAEL_UDID = ...); without it,
# the first iPhone on a cable is used.
set -euo pipefail
cd "$(dirname "$0")"

want=$(sed -n 's/^YAEL_UDID *= *//p' Local.xcconfig 2>/dev/null || true)
json=$(mktemp)
xcrun devicectl list devices --json-output "$json" >/dev/null
udid=$(python3 - "$json" "$want" <<'EOF'
import json, sys
devs = json.load(open(sys.argv[1]))["result"]["devices"]
want = sys.argv[2].strip()
for d in devs:
    hw, conn = d["hardwareProperties"], d["connectionProperties"]
    if want and hw.get("udid") == want and conn.get("tunnelState") == "connected":
        print(want); break
    if not want and hw.get("deviceType") == "iPhone" and conn.get("transportType") == "wired":
        print(hw["udid"]); break
EOF
)
if [ -z "$udid" ]; then
  echo "Yael's iPhone isn't reachable. Unlock it on the same Wi-Fi as this Mac, or connect it by cable, and run again."
  exit 1
fi
echo "Installing on $udid"

# Her sync code lives in Local.xcconfig too (KID_SYNC_CODE = ...), which Xcode reads.
grep -q "KID_SYNC_CODE *= *[a-z0-9-]" Local.xcconfig 2>/dev/null \
  || echo "Warning: no KID_SYNC_CODE in ios/Local.xcconfig. Progress will stay on the phone only."

xcodegen generate >/dev/null
xcodebuild -project Studio.xcodeproj -scheme Studio -configuration Release \
  -destination "id=$udid" -derivedDataPath build \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration build -quiet
xcrun devicectl device install app --device "$udid" build/Build/Products/Release-iphoneos/Studio.app
echo "Done."

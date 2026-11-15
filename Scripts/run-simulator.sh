#!/bin/zsh
# Builds SideQuest, boots an iPhone simulator, installs the app, simulates a London location
# and launches it, streaming the app's console output. Stop with Ctrl-C.
#
#   Scripts/run-simulator.sh                 # iPhone 15 Pro
#   DEVICE="iPhone 15" Scripts/run-simulator.sh
set -euo pipefail
cd "$(dirname "$0")/.."

DEVICE="${DEVICE:-iPhone 15 Pro}"
BUNDLE_ID="dev.sidequest.SideQuest"
DERIVED="build/DerivedData"
LAT_LON="${LAT_LON:-51.51174,-0.12302}"   # Covent Garden, London

UDID=$(xcrun simctl list devices available | grep -E "^ +$DEVICE \(" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
if [[ -z "$UDID" ]]; then
  echo "No available simulator named \"$DEVICE\". Available devices:" >&2
  xcrun simctl list devices available | grep -E "iPhone" >&2
  exit 1
fi

echo "▸ Building for $DEVICE ($UDID)…"
xcodebuild -project SideQuest.xcodeproj -scheme SideQuest -configuration Debug \
  -destination "id=$UDID" -derivedDataPath "$DERIVED" build -quiet

echo "▸ Booting simulator…"
xcrun simctl boot "$UDID" 2>/dev/null || true
SIM_APP="$(xcode-select -p)/Applications/Simulator.app"
if [[ -d "$SIM_APP" ]]; then
  open -a "$SIM_APP" --args -CurrentDeviceUDID "$UDID"
elif open -a Simulator 2>/dev/null; then
  :
else
  echo "⚠︎ Simulator.app isn't installed on this Mac, so the simulator runs without a window."
  echo "  Install the iOS simulator in Xcode → Settings → Components, or run on your iPhone (see README)."
fi
xcrun simctl bootstatus "$UDID" -b >/dev/null

echo "▸ Installing and launching…"
xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/SideQuest.app"
xcrun simctl location "$UDID" set "$LAT_LON" || true
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
echo "▸ SideQuest is running in the Simulator. (Demo mode is the default in the simulator.)"
exec xcrun simctl launch --console-pty "$UDID" "$BUNDLE_ID"

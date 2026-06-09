#!/bin/zsh
# Conductor "Run" button → build + install + launch THIS workspace on a connected
# iPhone. Runs from the workspace directory (Conductor's contract), so it always
# builds the worktree the agent is editing — never a stale separate checkout. This
# is the structural guard against "I fixed it but the build didn't change" (which
# happens when Xcode is open on ~/code/camusean while the agent edits a worktree).
#
# Device selection: honors $CAMUSEAN_DEVICE_ID if set, else the first paired device.
# (Benja usually has two attached — iPhone 14 primary, iPhone 17 Pro secondary —
# so export CAMUSEAN_DEVICE_ID to pin one.)
set -euo pipefail

BUNDLE_ID="com.bdelasoie.camusean"
SCHEME="camusean"
DERIVED="./build/DerivedData"

DEVICE_ID="${CAMUSEAN_DEVICE_ID:-}"
if [[ -z "$DEVICE_ID" ]]; then
  # Pick the first usable device. Match either "available (paired)" or "connected"
  # (the tunnel-active state) and require a UDID on the line, so we don't miss a
  # ready device just because it's currently connected rather than merely paired.
  DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
    | awk -F'  +' '/(available|connected)/ && /[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}/ {print $3; exit}')
fi
if [[ -z "$DEVICE_ID" ]]; then
  echo "No paired iPhone found. Connect a device (or set CAMUSEAN_DEVICE_ID)." >&2
  exit 1
fi
echo "▸ Target device: $DEVICE_ID"

echo "▸ Building $SCHEME from $(pwd) …"
xcodebuild \
  -project camusean.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  build

APP="$DERIVED/Build/Products/Debug-iphoneos/camusean.app"
echo "▸ Installing $APP …"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP"

echo "▸ Launching $BUNDLE_ID …"
# Right after install the device tunnel is often not ready yet, or the screen briefly
# re-locked — devicectl then returns CoreDeviceError 10002 ("Locked"). It's transient,
# so wait and retry a few times instead of giving up (this is what makes Cmd+R / the
# Run button "just work" without a manual tap).
launched=0
for attempt in 1 2 3 4 5 6; do
  if xcrun devicectl device process launch --device "$DEVICE_ID" --terminate-existing "$BUNDLE_ID"; then
    launched=1
    break
  fi
  echo "  …launch attempt $attempt failed (device waking/locked?), retrying in 2s…" >&2
  sleep 2
done
if [[ "$launched" == "1" ]]; then
  echo "✓ Running the current workspace build on device."
else
  # Still failing after retries — the phone is genuinely locked or asleep. The build is
  # already installed, so unlocking + tapping the icon (or re-running) will open it.
  echo "⚠︎ Installed OK, but couldn't auto-launch after retries. Unlock the phone and tap the app icon, or re-run." >&2
fi

#!/bin/bash
#
# Capture the App Store screenshot set into appstore/screenshots/.
#
# App Store Connect's primary required iPhone size is the 6.9" class = 1320x2868 on
# an iPhone 17 Pro Max simulator. Minimum 1 screenshot, maximum 10, PNG or JPEG, and
# NO alpha channel (XCUIScreenshot PNGs are already opaque — verify anyway, below).
#
# Screens that show saved words (Review) look like an empty shell on a fresh
# simulator. Pass a SwiftData store directory as $1 to seed one first, e.g. pulled
# off a real device with:
#
#   xcrun devicectl device copy from --device <udid> \
#     --domain-type appDataContainer --domain-identifier com.bdelasoie.camusean \
#     --source "Library/Application Support" --destination /tmp/camusean-container
#
# Usage:
#   ./scripts/capture-screenshots.sh                          # whatever is on the sim
#   ./scripts/capture-screenshots.sh /tmp/camusean-container  # seed real data first
#
# TWO SIMULATOR QUIRKS THIS SCRIPT WORKS AROUND — both cost real debugging time:
#
#  1. If the simulator is ALREADY BOOTED when `xcodebuild test` starts, the UI test
#     runner intermittently dies with:
#         "Application failed preflight checks" / Busy (SBMainWorkspace)
#     Letting xcodebuild boot the device itself avoids it. But `simctl
#     get_app_container` REQUIRES a booted device, so seeding has to boot, seed, and
#     then shut down again before the capture run.
#
#  2. That same preflight failure also happens at random with no booted device. It is
#     flaky, not deterministic — the identical command can fail then succeed. Hence
#     the retry loop.
#
set -euo pipefail

DEVICE_NAME="${DEVICE_NAME:-iPhone 17 Pro Max}"
OS_VERSION="${OS_VERSION:-26.5}"
BUNDLE_ID="com.bdelasoie.camusean"
SEED_DIR="${1:-}"
ATTEMPTS="${ATTEMPTS:-3}"

cd "$(dirname "${BASH_SOURCE[0]}")/.."
OUT="appstore/screenshots"
DD="/tmp/camusean-shots-dd"
RESULTS="/tmp/camusean-screenshots.xcresult"
LOG="/tmp/camusean-screenshots.log"

run_capture() {   # -> 0 on success
    rm -rf "$RESULTS"
    xcodebuild test \
        -project camusean.xcodeproj \
        -scheme camusean \
        -destination "platform=iOS Simulator,name=$DEVICE_NAME,OS=$OS_VERSION" \
        -only-testing:camuseanUITests/ScreenshotTests \
        -derivedDataPath "$DD" \
        -resultBundlePath "$RESULTS" \
        >"$LOG" 2>&1
}

capture_with_retry() {
    for attempt in $(seq 1 "$ATTEMPTS"); do
        xcrun simctl shutdown all >/dev/null 2>&1 || true
        sleep 8
        if run_capture; then
            echo "    capture succeeded (attempt $attempt)"
            return 0
        fi
        echo "    attempt $attempt failed" >&2
    done
    echo "error: capture failed after $ATTEMPTS attempts. Tail of $LOG:" >&2
    tail -20 "$LOG" >&2
    return 1
}

echo "==> Resolving simulator: $DEVICE_NAME ($OS_VERSION)"
UDID=$(xcrun simctl list devices available \
        | awk -v d="$DEVICE_NAME" 'index($0, d) {match($0, /[0-9A-F-]{36}/); if (RSTART) {print substr($0, RSTART, RLENGTH); exit}}')
[ -n "$UDID" ] || { echo "error: no available simulator named '$DEVICE_NAME'" >&2; exit 1; }
echo "    $UDID"

if [ -n "$SEED_DIR" ]; then
    [ -f "$SEED_DIR/default.store" ] || { echo "error: $SEED_DIR/default.store not found" >&2; exit 1; }

    # Pass 1 exists only to make xcodebuild install the app, so a data container
    # exists to seed. Its screenshots are discarded.
    echo "==> Pass 1/2: installing app (screenshots discarded)"
    capture_with_retry

    echo "==> Seeding store from $SEED_DIR"
    xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
    CONTAINER=$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)
    case "$CONTAINER" in
        /*) ;;
        *)  echo "error: could not resolve app container: $CONTAINER" >&2; exit 1;;
    esac
    mkdir -p "$CONTAINER/Library/Application Support"
    cp "$SEED_DIR"/default.store* "$CONTAINER/Library/Application Support/"
    echo "    seeded $(sqlite3 "$CONTAINER/Library/Application Support/default.store" 'SELECT COUNT(*) FROM ZWORD;' 2>/dev/null || echo '?') words"

    echo "==> Pass 2/2: capturing with seeded data"
fi

capture_with_retry

echo "==> Exporting to $OUT"
rm -rf "$OUT" /tmp/camusean-shots-export
mkdir -p "$OUT" /tmp/camusean-shots-export
xcrun xcresulttool export attachments --path "$RESULTS" --output-path /tmp/camusean-shots-export >/dev/null 2>&1

python3 - "$OUT" <<'PY'
import json, os, shutil, sys
out, src = sys.argv[1], "/tmp/camusean-shots-export"
manifest = os.path.join(src, "manifest.json")
if not os.path.exists(manifest):
    sys.exit("error: no manifest.json in export — nothing captured?")
count = 0
for test in json.load(open(manifest)):
    for att in test.get("attachments", []):
        name = att.get("suggestedHumanReadableName", "")
        if not name.endswith(".png"):
            continue
        # xcresulttool suffixes names with _<index>_<uuid>; keep the leading label.
        shutil.move(os.path.join(src, att["exportedFileName"]),
                    os.path.join(out, name.split("_")[0] + ".png"))
        count += 1
print(f"    {count} screenshot(s)")
PY

echo ""
echo "Verifying App Store requirements (6.9\" = 1320x2868, no alpha):"
fail=0
for f in "$OUT"/*.png; do
    read -r w h a < <(sips -g pixelWidth -g pixelHeight -g hasAlpha "$f" 2>/dev/null \
                      | awk '/pixelWidth|pixelHeight|hasAlpha/{printf "%s ", $2} END{print ""}')
    status="ok"
    { [ "$w" = "1320" ] && [ "$h" = "2868" ] && [ "$a" = "no" ]; } || { status="MISMATCH"; fail=1; }
    printf "  %-26s %sx%s alpha=%s  %s\n" "$(basename "$f")" "$w" "$h" "$a" "$status"
done
[ "$fail" -eq 0 ] || { echo "error: at least one screenshot does not meet App Store requirements" >&2; exit 1; }
echo ""
echo "Done — upload these in App Store Connect under the 6.9\" display size."

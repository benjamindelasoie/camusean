#!/bin/bash
#
# Archive Camusean for distribution and (optionally) upload it to App Store Connect.
#
#   ./scripts/archive-and-upload.sh            # archive + export a signed .ipa, stop
#   ./scripts/archive-and-upload.sh --upload   # ...and push it to App Store Connect
#   ./scripts/archive-and-upload.sh --skip-preflight
#
# Uploading uses the Apple ID already signed into Xcode, so there is no API key or
# app-specific password to manage. It is opt-in because an upload is not reversible:
# a build number, once consumed, cannot be reused.
#
# Verified working 2026-07-28: archive and export both succeed and produce an .ipa
# signed by "Apple Distribution: Benjamin Delasoie (LWQ9NP6HVT)".
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

ARCHIVE="/tmp/camusean.xcarchive"
EXPORT_DIR="/tmp/camusean-export"
OPTIONS="appstore/ExportOptions.plist"
DO_UPLOAD=0
SKIP_PREFLIGHT=0

for arg in "$@"; do
    case "$arg" in
        --upload)         DO_UPLOAD=1;;
        --skip-preflight) SKIP_PREFLIGHT=1;;
        *) echo "unknown option: $arg" >&2; exit 1;;
    esac
done

if [ "$SKIP_PREFLIGHT" -eq 0 ]; then
    echo "==> Preflight"
    if ! ./scripts/preflight-submission.sh; then
        echo "" >&2
        echo "Refusing to archive with blockers outstanding. Fix them, or re-run with" >&2
        echo "--skip-preflight if you know what you are doing." >&2
        exit 1
    fi
fi

echo ""
echo "==> Archiving (Release)"
rm -rf "$ARCHIVE"
xcodebuild archive \
    -project camusean.xcodeproj \
    -scheme camusean \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    -allowProvisioningUpdates \
    >/tmp/camusean-archive.log 2>&1 \
  || { echo "error: archive failed. Tail:" >&2; tail -25 /tmp/camusean-archive.log >&2; exit 1; }
echo "    $ARCHIVE"

echo ""
echo "==> Exporting signed .ipa"
rm -rf "$EXPORT_DIR"
if [ "$DO_UPLOAD" -eq 1 ]; then
    # Override destination rather than editing ExportOptions.plist, so "export" stays
    # the safe default and uploading is always an explicit act.
    TMP_OPTIONS=$(mktemp -t camusean-export-options).plist
    cp "$OPTIONS" "$TMP_OPTIONS"
    /usr/libexec/PlistBuddy -c "Set :destination upload" "$TMP_OPTIONS"
    OPTIONS="$TMP_OPTIONS"
    echo "    destination = upload (App Store Connect)"
fi

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportOptionsPlist "$OPTIONS" \
    -exportPath "$EXPORT_DIR" \
    -allowProvisioningUpdates \
    >/tmp/camusean-export.log 2>&1 \
  || { echo "error: export failed. Tail:" >&2; tail -25 /tmp/camusean-export.log >&2; exit 1; }

if [ "$DO_UPLOAD" -eq 1 ]; then
    echo ""
    echo "Uploaded. Processing usually takes a few minutes; you will get an email."
    echo "Then: App Store Connect > TestFlight > Internal Testing to add your friend"
    echo "(internal testing needs no review at all)."
else
    IPA=$(find "$EXPORT_DIR" -name "*.ipa" | head -1)
    echo "    $IPA"
    echo ""
    echo "Signed by:"
    UNPACK=$(mktemp -d)
    ( cd "$UNPACK" && unzip -q "$IPA" && codesign -dvv Payload/*.app 2>&1 | grep "^Authority=Apple" | head -1 | sed 's/^/    /' )
    rm -rf "$UNPACK"
    echo ""
    echo "Nothing has been uploaded. Re-run with --upload when ready."
fi

#!/bin/bash
#
# Release guard: fail the build if the /ios-qa DebugBridge harness is wired into
# the app target.
#
# WHY THIS EXISTS
#   Camusean's first App Store submission was rejected (code-50) because the
#   DebugBridge SPM package shipped inside the app target. It was removed in
#   5089df6 — but /ios-qa re-adds it every time it runs, and /ios-clean is a
#   manual step that has to be remembered. Remembering is not a control.
#   This turns "don't forget" into "cannot happen."
#
# SEMANTICS
#   Debug builds are left alone on purpose — that is exactly when DebugBridge is
#   supposed to be present, so /ios-qa keeps working untouched. Only Release
#   (archive / TestFlight / App Store) is guarded.
#
# SANDBOXING
#   The project sets ENABLE_USER_SCRIPT_SANDBOXING = YES, so this script may only
#   read files declared as inputPaths on its build phase (the script itself and
#   project.pbxproj) and write to its declared outputPath. The source-import scan
#   below needs the whole source tree, which cannot be declared, so it runs only
#   outside the sandbox (manual invocation). That is not a coverage hole: the
#   pbxproj check is the one that catches the actual rejection cause, and an
#   `import DebugBridge` without the package fails to compile anyway.
#
# WIRING
#   Run Script build phase on the `camusean` target. Also runnable by hand, where
#   it performs BOTH checks:
#       CONFIGURATION=Release ./scripts/verify-no-debug-bridge.sh
#
set -euo pipefail

# Fall back to the repo root so the script works standalone, not just under Xcode.
SRCROOT="${SRCROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONFIGURATION="${CONFIGURATION:-Release}"

# Stamp file lets Xcode's dependency analysis track this phase, so it re-runs only
# when project.pbxproj or this script changes — which is the only way DebugBridge
# can get wired in. Without an output, Xcode warns that the phase runs every build.
stamp="${SCRIPT_OUTPUT_FILE_0:-}"
write_stamp() {
    if [ -n "$stamp" ]; then
        mkdir -p "$(dirname "$stamp")"
        printf 'checked %s\n' "$CONFIGURATION" > "$stamp"
    fi
}

if [ "$CONFIGURATION" != "Release" ]; then
    echo "note: DebugBridge guard skipped (configuration=$CONFIGURATION, only Release is guarded)"
    write_stamp
    exit 0
fi

failed=0

# 1. Project wiring — the actual cause of the code-50 rejection. Catches the
#    package reference, the target dependency, and the link phase in one check.
if grep -q "DebugBridge" "$SRCROOT/camusean.xcodeproj/project.pbxproj" 2>/dev/null; then
    echo "error: DebugBridge is referenced in project.pbxproj but this is a Release build."
    echo "error: This is what caused the App Store code-50 rejection. Run /ios-clean before archiving."
    failed=1
fi

# 2. Source wiring — only reachable outside the script sandbox. Report explicitly
#    whether it ran, so a skipped check never reads as a passed one.
if [ -r "$SRCROOT/camusean" ] && grep -rn --include="*.swift" "import DebugBridge" "$SRCROOT/camusean" 2>/dev/null; then
    echo "error: The above files import DebugBridge in a Release build. Run /ios-clean."
    failed=1
elif [ ! -r "$SRCROOT/camusean" ]; then
    echo "note: source-import scan skipped (script sandbox); project.pbxproj check above still ran."
fi

if [ "$failed" -ne 0 ]; then
    exit 1
fi

echo "note: DebugBridge guard passed — app target is clean for Release."
write_stamp

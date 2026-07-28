#!/bin/bash
#
# Check everything that must be true before archiving Camusean for TestFlight or
# App Review. Read-only: it inspects, it never changes anything.
#
#   ./scripts/preflight-submission.sh            # skip the test suite (fast)
#   ./scripts/preflight-submission.sh --tests    # also run the unit suite
#
# Exit 0 when nothing is blocking. Checks are split into BLOCKERS (submission will
# fail or be rejected) and WARNINGS (worth knowing, not fatal).
#
set -uo pipefail   # deliberately NOT -e: every check must run, even after a failure

cd "$(dirname "${BASH_SOURCE[0]}")/.."

BLOCKERS=0
WARNINGS=0
pass()  { printf "  \033[32m✓\033[0m %s\n" "$1"; }
block() { printf "  \033[31m✗ BLOCKER\033[0m %s\n" "$1"; BLOCKERS=$((BLOCKERS+1)); }
warn()  { printf "  \033[33m!\033[0m %s\n" "$1"; WARNINGS=$((WARNINGS+1)); }

echo ""
echo "Camusean — submission preflight"
echo "================================"

echo ""
echo "Seeded API key"
if [ -f camusean/Secrets.plist ]; then
    key=$(/usr/libexec/PlistBuddy -c "Print :AnthropicAPIKey" camusean/Secrets.plist 2>/dev/null || echo "")
    case "$key" in
        sk-ant-*) pass "camusean/Secrets.plist holds a key (${#key} chars)";;
        "")       block "Secrets.plist has no AnthropicAPIKey — the app will not seed";;
        *)        block "Secrets.plist still holds the placeholder — the app will not seed";;
    esac
else
    block "camusean/Secrets.plist absent. Testers and App Review hit the key wall and
             the app cannot look up a word (Guideline 2.1). Fix:
             ./scripts/set-api-key.sh sk-ant-..."
fi
if git ls-files --error-unmatch camusean/Secrets.plist >/dev/null 2>&1; then
    block "camusean/Secrets.plist is TRACKED BY GIT — the key is committed. Remove it."
else
    pass "Secrets.plist is not tracked by git"
fi

echo ""
echo "Build identity"
MV=$(grep -m1 "MARKETING_VERSION" camusean.xcodeproj/project.pbxproj | sed 's/.*= *//;s/;//')
BV=$(grep -m1 "CURRENT_PROJECT_VERSION" camusean.xcodeproj/project.pbxproj | sed 's/.*= *//;s/;//')
pass "version $MV, build $BV (App Store Connect rejects a re-used build number)"
grep -q "ITSAppUsesNonExemptEncryption = NO" camusean.xcodeproj/project.pbxproj \
  && pass "export compliance declared (no upload prompt)" \
  || warn "ITSAppUsesNonExemptEncryption not set — you'll be asked at every upload"

echo ""
echo "Privacy"
[ -f camusean/PrivacyInfo.xcprivacy ] \
  && pass "PrivacyInfo.xcprivacy present" \
  || block "PrivacyInfo.xcprivacy missing — UserDefaults use triggers ITMS-91053"
grep -q "CA92.1" camusean/PrivacyInfo.xcprivacy 2>/dev/null \
  && pass "UserDefaults declared with reason CA92.1" \
  || block "privacy manifest does not declare the UserDefaults required-reason API"
for f in appstore/privacy-labels-and-age-rating.md appstore/review-notes.txt appstore/app-store-metadata.md; do
    [ -f "$f" ] && pass "$(basename "$f") present" || block "$f missing"
done

echo ""
echo "QA harness must not ship"
if grep -q "DebugBridge" camusean.xcodeproj/project.pbxproj; then
    block "DebugBridge is referenced in project.pbxproj — this caused the code-50
             rejection. Run /ios-clean before archiving."
else
    pass "no DebugBridge references in the project"
fi

echo ""
echo "Screenshots (6.9\" = 1320x2868, no alpha)"
shots=(appstore/screenshots/*.png)
if [ ! -e "${shots[0]}" ]; then
    block "no screenshots in appstore/screenshots/ — required for the App Store listing
             (NOT required for TestFlight). Run ./scripts/capture-screenshots.sh"
else
    bad=0
    for f in "${shots[@]}"; do
        read -r w h a < <(sips -g pixelWidth -g pixelHeight -g hasAlpha "$f" 2>/dev/null \
                          | awk '/pixelWidth|pixelHeight|hasAlpha/{printf "%s ", $2} END{print ""}')
        { [ "$w" = "1320" ] && [ "$h" = "2868" ] && [ "$a" = "no" ]; } || {
            block "$(basename "$f") is ${w}x${h} alpha=$a — does not meet the spec"; bad=1; }
    done
    [ "$bad" -eq 0 ] && pass "${#shots[@]} screenshot(s), all 1320x2868 with no alpha"
fi

echo ""
echo "Public URLs (App Review must reach these without logging in)"
check_url() {
    local url="$1" label="$2"
    local final code
    final=$(curl -sL -o /dev/null -w '%{url_effective}' --max-time 20 "$url" 2>/dev/null)
    code=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 20 "$url" 2>/dev/null)
    if [ "$code" != "200" ]; then
        block "$label returned HTTP $code — $url"
    elif [[ "$final" == *"/login"* || "$final" == *"vercel.com"* ]]; then
        # A protected deployment answers 200 while redirecting to a login page, so the
        # status code alone is not evidence. This is the trap worth guarding.
        block "$label redirects to a login wall ($final) — a reviewer cannot read it"
    else
        pass "$label reachable and public"
    fi
}
check_url "https://camusean.vercel.app/privacy.html" "privacy policy"
check_url "https://camusean.vercel.app/" "support / marketing site"

echo ""
echo "Repository"
[ -z "$(git status --porcelain)" ] && pass "working tree clean" || warn "uncommitted changes present"
if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    [ "$(git rev-list --count '@{u}'..HEAD)" -eq 0 ] && pass "branch pushed" || warn "unpushed commits"
fi

if [ "${1:-}" = "--tests" ]; then
    echo ""
    echo "Unit tests"
    if xcodebuild test -project camusean.xcodeproj -scheme camusean \
         -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
         -only-testing:camuseanTests -derivedDataPath /tmp/camusean-preflight >/tmp/preflight-tests.log 2>&1; then
        pass "unit suite passes"
    else
        block "unit suite FAILED — see /tmp/preflight-tests.log"
    fi
fi

echo ""
echo "================================"
if [ "$BLOCKERS" -eq 0 ]; then
    echo "READY — $WARNINGS warning(s), nothing blocking."
    echo ""
    echo "Next: Xcode > Product > Archive, then Distribute App > App Store Connect."
    echo "For your friend: TestFlight > Internal Testing needs no review at all."
    exit 0
else
    echo "NOT READY — $BLOCKERS blocker(s), $WARNINGS warning(s)."
    echo "See appstore/SUBMISSION-CHECKLIST.md."
    exit 1
fi

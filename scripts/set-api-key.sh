#!/bin/bash
#
# Write camusean/Secrets.plist so builds ship with a seeded Anthropic API key.
#
# WHY THIS MATTERS
#   Without it, KeychainService.seedAPIKeyIfNeeded() finds nothing and anyone who is
#   not you — a TestFlight tester, an App Review reviewer — opens the app to an empty
#   key field and cannot look up a single word. App Review reads that as Guideline 2.1
#   (incomplete / functionality not accessible) and rejects.
#
#   Use a CAPPED, REVOCABLE key from https://console.anthropic.com with a low monthly
#   spend limit. The key ships inside the app bundle, so treat it as semi-public: it can
#   be extracted from the binary by anyone who cares to. The app also self-limits to
#   AnthropicService.dailyCap (200) lookups per day.
#
#   camusean/Secrets.plist is gitignored and must never be committed.
#
# Usage:
#   ./scripts/set-api-key.sh sk-ant-...           # write the key
#   ./scripts/set-api-key.sh --status             # is one configured?
#   ./scripts/set-api-key.sh --remove             # drop back to manual entry
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
TARGET="camusean/Secrets.plist"
TEMPLATE="Secrets.plist.example"

case "${1:-}" in
    --status|"")
        if [ -f "$TARGET" ]; then
            key=$(/usr/libexec/PlistBuddy -c "Print :AnthropicAPIKey" "$TARGET" 2>/dev/null || echo "")
            case "$key" in
                sk-ant-*) echo "configured: ${key:0:14}… (${#key} chars)";;
                "")       echo "$TARGET exists but has no AnthropicAPIKey — builds will NOT seed";;
                *)        echo "$TARGET still holds the placeholder — builds will NOT seed";;
            esac
        else
            echo "not configured: $TARGET is absent — builds will NOT seed a key"
            echo "run: ./scripts/set-api-key.sh sk-ant-..."
        fi
        exit 0
        ;;
    --remove)
        rm -f "$TARGET"
        echo "removed $TARGET — builds fall back to manual key entry in Settings"
        exit 0
        ;;
esac

KEY="$1"
case "$KEY" in
    sk-ant-*) ;;
    *) echo "error: key must start with 'sk-ant-'. seedAPIKeyIfNeeded() rejects anything else," >&2
       echo "       so a wrong prefix fails silently at runtime rather than here." >&2
       exit 1;;
esac

[ -f "$TEMPLATE" ] || { echo "error: $TEMPLATE missing" >&2; exit 1; }
cp "$TEMPLATE" "$TARGET"
/usr/libexec/PlistBuddy -c "Set :AnthropicAPIKey $KEY" "$TARGET"
plutil -lint "$TARGET" >/dev/null

# Belt and braces: this file must never reach the repo.
if ! git check-ignore -q "$TARGET"; then
    echo "error: $TARGET is NOT gitignored — refusing to leave a key at risk of commit" >&2
    rm -f "$TARGET"
    exit 1
fi

echo "wrote $TARGET (gitignored)"
echo "rebuild, then confirm Settings shows 'A key is already set up'."

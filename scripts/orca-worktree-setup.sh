#!/bin/bash
#
# Orca per-worktree setup hook.
#
# Runs once when Orca spins up a fresh worktree of camusean. Point the repo's
# setup script at it in the Orca app (Repo settings → Setup script):
#
#     bash scripts/orca-worktree-setup.sh
#
# Two jobs, both idempotent and safe to re-run:
#   1. Seed camusean/Secrets.plist from the primary checkout. That file is
#      gitignored (it carries the capped Anthropic key), so a new worktree
#      starts without it — device/TestFlight builds ship an empty key field and
#      the seeded-key UX breaks. We copy it over, never overwrite an existing one.
#   2. Pre-resolve SwiftPM packages so the first build in the worktree doesn't
#      stall on a cold package graph. Cheap: the package cache is shared globally.
#
# It never touches git and never fails the worktree create — a missing source
# Secrets.plist is a warning, not an error (Simulator dev works with manual key
# entry in Settings).
#
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
WORKTREE_ROOT="$(pwd)"
SECRETS="camusean/Secrets.plist"

# Locate the primary checkout via the shared git common dir. For a linked
# worktree this resolves to <primary>/.git; the primary itself no-ops harmlessly.
COMMON="$(git rev-parse --git-common-dir)"
case "$COMMON" in /*) ;; *) COMMON="$WORKTREE_ROOT/$COMMON";; esac
PRIMARY_ROOT="$(cd "$(dirname "$COMMON")" && pwd)"

echo "orca-setup: worktree=$WORKTREE_ROOT primary=$PRIMARY_ROOT"

# 1. Seed Secrets.plist ----------------------------------------------------
if [ -f "$SECRETS" ]; then
    echo "orca-setup: $SECRETS already present — leaving it untouched"
elif [ "$PRIMARY_ROOT" != "$WORKTREE_ROOT" ] && [ -f "$PRIMARY_ROOT/$SECRETS" ]; then
    cp "$PRIMARY_ROOT/$SECRETS" "$SECRETS"
    # Belt and braces: never let a copied key become committable.
    if git check-ignore -q "$SECRETS"; then
        echo "orca-setup: seeded $SECRETS from primary checkout (gitignored)"
    else
        echo "orca-setup: WARNING $SECRETS is not gitignored — removing to avoid commit risk" >&2
        rm -f "$SECRETS"
    fi
else
    echo "orca-setup: no source $SECRETS found — set one with ./scripts/set-api-key.sh sk-ant-... (or enter the key in Settings)"
fi

# 2. Pre-resolve SwiftPM packages -----------------------------------------
if command -v xcodebuild >/dev/null 2>&1; then
    echo "orca-setup: resolving SwiftPM packages…"
    xcodebuild -resolvePackageDependencies \
        -project camusean.xcodeproj -scheme camusean >/dev/null 2>&1 \
        && echo "orca-setup: packages resolved" \
        || echo "orca-setup: package resolve skipped (non-fatal)"
fi

echo "orca-setup: done"

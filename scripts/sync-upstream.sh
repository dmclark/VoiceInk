#!/usr/bin/env bash
set -euo pipefail

# Sync fork with upstream (Beingpax/VoiceInk) and merge into feature branch.
#
# Usage:
#   ./scripts/sync-upstream.sh              # default feature branch: voiceitt
#   ./scripts/sync-upstream.sh my-branch    # specify a different feature branch

FEATURE_BRANCH="${1:-feature/voiceitt}"
UPSTREAM_REMOTE="upstream"
UPSTREAM_BRANCH="main"

echo "==> Fetching upstream ($UPSTREAM_REMOTE)..."
git fetch "$UPSTREAM_REMOTE"

echo "==> Updating local main from $UPSTREAM_REMOTE/$UPSTREAM_BRANCH..."
git switch main
git merge "$UPSTREAM_REMOTE/$UPSTREAM_BRANCH" --no-edit

echo "==> Merging main into $FEATURE_BRANCH..."
git switch "$FEATURE_BRANCH"
git merge main --no-edit

echo "==> Done. You are now on '$FEATURE_BRANCH' with upstream changes merged."
echo "    Review any conflicts, then push when ready:"
echo "      git push origin main"
echo "      git push origin $FEATURE_BRANCH"

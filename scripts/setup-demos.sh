#!/usr/bin/env bash
# setup-demos.sh — push gate-node update + create & push a node demo repo.
# Run in Git Bash. Bypasses the gh-proxy insteadOf via GIT_CONFIG_GLOBAL + gh credential helper.
set -euo pipefail
export PATH="/c/Program Files/GitHub CLI:$PATH"

ORG=quality-gate-test
GH="/c/Program Files/GitHub CLI/gh.exe"
ROOT="/d/workingprojects/githubstudy"
# credential helper value (single-quoted so inner double-quotes stay literal)
HELPER='credential.helper=!"/c/Program Files/GitHub CLI/gh.exe" auth git-credential'

echo "=== 1. Push gate-node update to $ORG/.github ==="
cd "$ROOT/org-dotgithub"
git add -A
git commit -q -m "gate-node: tolerant install (ci or install) + test without --coverage" || echo "(nothing to commit)"
GIT_CONFIG_GLOBAL=/dev/null git -c "$HELPER" push "https://github.com/$ORG/.github.git" HEAD:main
echo "  done"

echo
echo "=== 2. Create + push demo-node ==="
"$GH" repo create "$ORG/demo-node" --public 2>/dev/null || echo "  (demo-node already exists, continuing)"
cd "$ROOT/demos/demo-node"
git init -q
git config user.email "ci@org.local"
git config user.name "Org CI"
git add -A
git commit -q -m "init: demo-node (validates the org quality gate)"
git branch -M main
GIT_CONFIG_GLOBAL=/dev/null git -c "$HELPER" push "https://github.com/$ORG/demo-node.git" HEAD:main
echo "  done"

echo
echo "✓ All pushed."
echo "  Watch CI:  https://github.com/$ORG/demo-node/actions"
echo "  Reusable gate: https://github.com/$ORG/.github/actions"
echo
echo "Tell me when the demo-node CI run finishes (green or red), or just say 'check'."

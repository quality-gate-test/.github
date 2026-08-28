#!/usr/bin/env bash
# fix-yaml.sh — push the pipe-in-description YAML fix to both .github and ci-gates,
# then trigger a fresh demo-node run via an empty commit.
set -euo pipefail
export PATH="/c/Program Files/GitHub CLI:$PATH"

ORG=quality-gate-test
ROOT="/d/workingprojects/githubstudy"
HELPER='credential.helper=!"/c/Program Files/GitHub CLI/gh.exe" auth git-credential'

echo "=== 1. Push YAML fix to .github ==="
cd "$ROOT/org-dotgithub"
git add -A && git commit -q -m "fix: quote descriptions containing pipe (gate-node/gate-java)" || echo "  (nothing to commit)"
GIT_CONFIG_GLOBAL=/dev/null git -c "$HELPER" push "https://github.com/$ORG/.github.git" HEAD:main
echo "  done"

echo
echo "=== 2. Copy fixed gates into ci-gates + push ==="
cp "$ROOT/org-dotgithub/.github/workflows/"gate-*.yml "$ROOT/org-cigates/.github/workflows/"
cd "$ROOT/org-cigates"
git add -A && git commit -q -m "fix: quote descriptions containing pipe (gate-node/gate-java)" || echo "  (nothing to commit)"
GIT_CONFIG_GLOBAL=/dev/null git -c "$HELPER" push "https://github.com/$ORG/ci-gates.git" HEAD:main
echo "  done"

echo
echo "=== 3. Trigger fresh demo-node run (empty commit) ==="
cd "$ROOT/demos/demo-node"
git commit --allow-empty -q -m "chore: trigger CI after gate YAML fix"
GIT_CONFIG_GLOBAL=/dev/null git -c "$HELPER" push "https://github.com/$ORG/demo-node.git" HEAD:main
echo "  done"

echo
echo "✓ Fixed + new run triggered. Say 'check' and I'll look at the result."

#!/usr/bin/env bash
# fix-reusable.sh — move reusable gates to a normal-named repo (ci-gates),
# re-point demo-node at it, and push. Resolves the empty referenced_workflows issue
# caused by hosting reusable workflows in the special `.github` repo.
set -euo pipefail
export PATH="/c/Program Files/GitHub CLI:$PATH"

ORG=quality-gate-test
GH="/c/Program Files/GitHub CLI/gh.exe"
ROOT="/d/workingprojects/githubstudy"
HELPER='credential.helper=!"/c/Program Files/GitHub CLI/gh.exe" auth git-credential'
CIGATES="$ROOT/org-cigates"

echo "=== 1. Build ci-gates repo content ==="
mkdir -p "$CIGATES/.github/workflows"
cp "$ROOT/org-dotgithub/.github/workflows/"gate-*.yml "$CIGATES/.github/workflows/"
printf '*.yml text eol=lf\n' > "$CIGATES/.gitattributes"
cat > "$CIGATES/README.md" <<'EOF'
# ci-gates

Shared reusable quality-gate workflows for the quality-gate-test org.
Repos reference these via:

    uses: quality-gate-test/ci-gates/.github/workflows/gate-<lang>.yml@main
EOF

echo "=== 2. Create + push ci-gates repo ==="
"$GH" repo create "$ORG/ci-gates" --public 2>/dev/null || echo "  (ci-gates already exists, continuing)"
cd "$CIGATES"
git init -q
git config user.email "ci@org.local"
git config user.name "Org CI"
git add -A
git commit -q -m "init: reusable quality gates (node/java/python)"
git branch -M main
GIT_CONFIG_GLOBAL=/dev/null git -c "$HELPER" push "https://github.com/$ORG/ci-gates.git" HEAD:main
echo "  pushed"

echo
echo "=== 3. Re-point demo-node ci.yml -> ci-gates, and push ==="
sed -i 's#quality-gate-test/.github/.github/workflows/#quality-gate-test/ci-gates/.github/workflows/#' "$ROOT/demos/demo-node/.github/workflows/ci.yml"
echo "  new uses line:"
grep 'uses:' "$ROOT/demos/demo-node/.github/workflows/ci.yml"
cd "$ROOT/demos/demo-node"
git add -A
git commit -q -m "ci: point reusable workflow to ci-gates repo"
GIT_CONFIG_GLOBAL=/dev/null git -c "$HELPER" push "https://github.com/$ORG/demo-node.git" HEAD:main
echo "  pushed"

echo
echo "✓ Done. New CI run triggered on demo-node. Say 'check' and I'll look."

#!/usr/bin/env bash
# onboard-repo.sh — one-command quality gate onboarding for an org repo.
#
# What it does, end to end:
#   1. fetch the right ci.yml template (node/python/java) from ORG/.github
#   2. drop it into the repo, open a PR
#   3. wait for the PR's gate / lint + test + build to pass (stops here if not)
#   4. merge the PR, wait for main's CI to pass
#   5. put branch protection on main (require PR + 3 checks + linear history)
#
# Prereq: the repo already has lint/test/build wired up (package.json scripts,
# pyproject ruff/mypy/pytest, or maven checkstyle). If not, step 3 fails and
# you go fix the repo — no protection is applied, so nothing is left half-locked.
#
# Usage:
#   ORG=quality-gate-test ./onboard-repo.sh <repo> <lang> [key=value ...]
#   ./onboard-repo.sh demo-node node package-manager=npm node-version=20
#   ./onboard-repo.sh data-pipe python python-version=3.12
#   ./onboard-repo.sh orders-svc java build-tool=gradle
set -euo pipefail

ORG="${ORG:-quality-gate-test}"
BRANCH="ci/add-quality-gate"
PROTECT_BRANCH="${PROTECT_BRANCH:-main}"
POLL_TIMEOUT="${POLL_TIMEOUT:-600}"   # seconds to wait per CI stage
POLL_INTERVAL="${POLL_INTERVAL:-15}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing: $1" >&2; exit 1; }; }
need gh; need git

[ $# -ge 2 ] || { echo "usage: $0 <repo> <lang> [key=value ...]" >&2; exit 1; }
REPO="$1"; LANG="$2"; shift 2

case "$LANG" in
  node|nodejs)   TPL="node-ci.yml" ;;
  python|py)     TPL="python-ci.yml" ;;
  java|maven|gradle) TPL="java-ci.yml" ;;
  *) echo "lang must be node|python|java (got: $LANG)" >&2; exit 1 ;;
esac

[ "$REPO" = ".github" ] && { echo "skip .github (infra repo, no app code)" >&2; exit 1; }

echo "==> $ORG/$REPO ($LANG)"
gh api "repos/$ORG/$REPO" --jq .full_name >/dev/null 2>&1 || { echo "repo not found: $ORG/$REPO" >&2; exit 1; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
ci_file="$work/ci.yml"

# 1. fetch template
gh api "repos/$ORG/.github/contents/.github/workflow-templates/$TPL" --jq '.content' | base64 -d > "$ci_file"

# apply extra inputs (key=value) into the with: block
for kv in "$@"; do
  k="${kv%%=*}"; v="${kv#*=}"
  [ "$k" = "$v" ] && { echo "bad input '$kv' (want key=value)" >&2; exit 1; }
  sed -i.bak "s|^\(      ${k}:\).*|\1 ${v}|" "$ci_file" && rm -f "$ci_file.bak"
done

# already onboarded?
if gh api "repos/$ORG/$REPO/contents/.github/workflows/ci.yml" >/dev/null 2>&1; then
  echo "  ci.yml already exists; skipping PR (delete it first to re-onboard)"
else
  # 2. clone, branch, commit, push, PR
  gh repo clone "$ORG/$REPO" "$work/repo" -- --depth 1 2>/dev/null
  cd "$work/repo"
  git checkout -b "$BRANCH"
  mkdir -p .github/workflows
  cp "$ci_file" .github/workflows/ci.yml
  git add .github/workflows/ci.yml
  git commit -m "ci: add org quality gate ($LANG)" -q
  git push -u origin "$BRANCH" 2>&1 | sed 's/^/  /'
  gh pr create -R "$ORG/$REPO" --head "$BRANCH" --base "$PROTECT_BRANCH" \
    --title "ci: add org quality gate" \
    --body "Auto-onboarded by onboard-repo.sh. Uses reusable workflow from \`$ORG/.github\`." \
    >/dev/null
  PR=$(gh pr list -R "$ORG/$REPO" --head "$BRANCH" --state open --json number --jq '.[0].number')
  echo "  PR #$PR opened"

  # 3. wait for PR checks
  echo "  waiting for CI (up to ${POLL_TIMEOUT}s)..."
  elapsed=0
  while [ $elapsed -lt $POLL_TIMEOUT ]; do
    # returns non-zero while checks are still running
    if gh pr checks "$PR" -R "$ORG/$REPO" --watch >/dev/null 2>&1; then break; fi
    sleep "$POLL_INTERVAL"; elapsed=$((elapsed + POLL_INTERVAL))
  done
  echo "  poll elapsed: ${elapsed}s"

  # collect results (no mapfile — macOS ships bash 3.2)
  results=$(gh pr checks "$PR" -R "$ORG/$REPO" --json name,state --jq '.[] | "    \(.name): \(.state)"' 2>/dev/null || true)
  echo "$results"
  if [ -z "$results" ]; then
    echo "  no check results; CI may not have triggered. Inspect PR #$PR." >&2; exit 1
  fi
  if echo "$results" | grep -Eq 'FAILURE|CANCELLED|TIMED_OUT|ACTION_REQUIRED'; then
    echo "  CI did not pass; fix the repo and re-run. PR #$PR left open." >&2; exit 1
  fi

  # 4. merge PR, then wait for main's push run
  gh pr merge "$PR" -R "$ORG/$REPO" --squash --delete-branch --admin >/dev/null 2>&1 \
    || gh pr merge "$PR" -R "$ORG/$REPO" --squash --delete-branch >/dev/null
  echo "  PR merged"
  cd "$work"; rm -rf repo

  echo "  waiting for main CI (up to ${POLL_TIMEOUT}s)..."
  elapsed=0
  while [ $elapsed -lt $POLL_TIMEOUT ]; do
    line=$(gh run list -R "$ORG/$REPO" --branch "$PROTECT_BRANCH" --limit 1 \
             --json status,conclusion --jq '.[0] | .status + "/" + (.conclusion // "null")' 2>/dev/null || echo "")
    case "$line" in completed/success) break ;; esac
    sleep "$POLL_INTERVAL"; elapsed=$((elapsed + POLL_INTERVAL))
  done
  echo "  main CI: $line"
  case "$line" in completed/success) ;; *) echo "  main CI not green; skipping protection." >&2; exit 1 ;; esac
fi

# 5. branch protection on main (equivalent to the org gate; rulesets API schema
#    changed, so we use the stable protection endpoint).
echo "  applying branch protection on $PROTECT_BRANCH..."
cat <<JSON | gh api -X PUT "repos/$ORG/$REPO/branches/$PROTECT_BRANCH/protection" --input - >/dev/null
{
  "required_status_checks": {"strict": true, "contexts": ["gate / lint","gate / test","gate / build"]},
  "enforce_admins": true,
  "required_pull_request_reviews": {"required_approving_review_count": 0, "dismiss_stale_reviews": true, "require_code_owner_reviews": false, "require_last_push_approval": false},
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
echo "  done. $ORG/$REPO is gated on $PROTECT_BRANCH (PR + gate/lint+test+build + admin enforced)."

#!/usr/bin/env bash
# create-repo-ruleset.sh — apply a REPOSITORY-LEVEL ruleset to every (non-archived)
# repo in the org. Free-plan compatible (org-level rulesets need Enterprise/Team).
#
# Run AFTER each repo's ci.yml has run at least once, so the check contexts are
# registered with GitHub (a context can only be *required* once it has reported).
#
# Uses gh's built-in --jq filter (no system jq needed).
#
# Usage:  ORG=quality-gate-test ./create-repo-ruleset.sh
set -euo pipefail
export PATH="/c/Program Files/GitHub CLI:$PATH"

ORG="${ORG:-quality-gate-test}"
ENFORCE="${ENFORCE:-active}"   # "active" = enforce, "evaluate" = dry-run

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not found." >&2; exit 1
fi

payload() {
  cat <<JSON
{
  "target": "branch",
  "source": "RepositoryConfig",
  "enforcement": "$ENFORCE",
  "name": "quality-gate",
  "conditions": {
    "ref_name": {
      "include": ["refs/heads/main","refs/heads/master","refs/heads/develop","refs/heads/release/*"],
      "exclude": []
    }
  },
  "rules": [
    { "type": "required_status_checks",
      "parameters": { "strict": true,
        "contexts": ["gate / lint","gate / test","gate / build"] } },
    { "type": "pull_request",
      "parameters": { "required_approving_review_count": 1,
        "dismiss_stale_reviews": true,
        "require_code_owner_reviews": false,
        "require_last_push_approval": false } },
    { "type": "required_linear_history" },
    { "type": "deletion" }
  ]
}
JSON
}

echo "Listing non-archived repos in $ORG ..."
# gh's internal --jq works without system jq.
mapfile -t REPOS < <(gh repo list "$ORG" --limit 200 --json name,isArchived --jq '.[] | select(.isArchived == false) | .name')

if [ "${#REPOS[@]}" -eq 0 ]; then
  echo "No repos found in $ORG." >&2; exit 0
fi

for repo in "${REPOS[@]}"; do
  [ "$repo" = ".github" ] && { echo "  skip .github (no app code)"; continue; }
  echo "==> $repo"
  # delete a prior same-named ruleset so re-runs are idempotent
  existing=$(gh api "repos/$ORG/$repo/rulesets" --jq '.[] | select(.name=="quality-gate") | .id' 2>/dev/null || true)
  for id in $existing; do
    gh api -X DELETE "repos/$ORG/$repo/rulesets/$id" >/dev/null 2>&1 || true
  done
  payload | gh api -X POST "repos/$ORG/$repo/rulesets" --input - >/dev/null && echo "    applied ($ENFORCE)" || echo "    FAILED"
done

echo
echo "Done. Verify:  gh api repos/$ORG/demo-node/rulesets"

#!/usr/bin/env bash
# create-repo-ruleset.sh — apply a REPOSITORY-LEVEL ruleset to every repo in the org.
#
# This is the free-plan-compatible alternative to org-level rulesets. Each repo
# gets an identical ruleset on its main branch; the script makes the rollout uniform.
# Re-run after adding new repos, or after editing CHECK_CONTEXTS, to refresh them all.
#
# Run AFTER the reusable workflows exist in ORG/.github AND after each repo's
# ci.yml has run at least once successfully (so the check contexts are registered).
#
# Usage:  ORG=quality-gate-test ./create-repo-ruleset.sh
# Requires: gh (authed), jq.
set -euo pipefail

ORG="${ORG:-quality-gate-test}"
BRANCHES="${BRANCHES:-main master develop release/*}"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not found." >&2; exit 1
fi

# Required check contexts. The caller job in ci.yml is named `gate`; the reusable
# jobs inside are `lint`/`test`/`build`, so GitHub shows them as "gate / lint" etc.
# IMPORTANT: a context can only be *required* after it has run once on the branch.
CHECK_CONTEXTS='["gate / lint", "gate / test", "gate / build"]'

# Build branch include array dynamically.
build_payload() {
  jq -n --argjson checks "$CHECK_CONTEXTS" --argjson branches "$(printf '"refs/heads/%s"\n' $BRANCHES | jq -s .)" '{
    target: "branch",
    "source": "RepositoryConfig",
    enforcement: "active",
    name: "quality-gate",
    "conditions": { "ref_name": { "include": $branches, "exclude": [] } },
    rules: [
      { "type": "required_status_checks",
        "parameters": { "strict": true, "contexts": $checks } },
      { "type": "pull_request",
        "parameters": { "required_approving_review_count": 1, "dismiss_stale_reviews": true } },
      { "type": "required_linear_history" },
      { "type": "deletion" }
    ]
  }'
}

echo "Listing non-archived repos in $ORG ..."
mapfile -t REPOS < <(gh repo list "$ORG" --limit 200 --json name,isArchived --jq '.[] | select(.isArchived == false) | .name')

if [ "${#REPOS[@]}" -eq 0 ]; then
  echo "No repos found in $ORG. Create some repos with ci.yml first (see bootstrap-ci.sh)." >&2
  exit 0
fi

for repo in "${REPOS[@]}"; do
  [ "$repo" = ".github" ] && { echo "  skip .github (no app code)"; continue; }
  echo "==> $repo"
  # delete any prior same-named ruleset (so re-runs are idempotent-ish)
  existing=$(gh api "repos/$ORG/$repo/rulesets" --jq '.[] | select(.name=="quality-gate") | .id' 2>/dev/null || true)
  for id in $existing; do
    gh api -X DELETE "repos/$ORG/$repo/rulesets/$id" >/dev/null 2>&1 || true
  done
  build_payload | gh api -X POST "repos/$ORG/$repo/rulesets" --input - >/dev/null && echo "    applied" || echo "    FAILED"
done

echo
echo "Done. Verify:  gh api repos/$ORG/<repo>/rulesets | jq"
echo
echo "NOTE: required_status_checks only blocks merges for contexts that have already run"
echo "on the target branch. If a check hasn't run yet GitHub shows it as 'expected'."

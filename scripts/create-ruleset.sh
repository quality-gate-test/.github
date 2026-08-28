#!/usr/bin/env bash
# create-ruleset.sh — create an ORG-LEVEL ruleset enforcing required checks + PRs.
# Applies to all repos in the org (adjust conditions to target a subset).
#
# Run AFTER the reusable workflows exist in ORG/.github AND after each repo's
# ci.yml has produced at least one successful run (so the check contexts are
# registered — GitHub only accepts registered contexts as "required").
#
# Usage:  ORG=__ORG__ ./create-ruleset.sh
# Requires: gh (authed), jq.
set -euo pipefail

ORG="${ORG:-__ORG__}"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not found." >&2; exit 1
fi

# The job names that become required status checks.
# These match the `lint`/`test`/`build` jobs in gate-*.yml (prefixed by "CI / ").
# IMPORTANT: required checks only block merges once they have run at least once
# on a PR. Gate the ruleset rollout to "evaluate" mode first if unsure.
CHECK_CONTEXTS='["gate / lint", "gate / test", "gate / build"]'

payload=$(jq -n \
  --arg org "$ORG" \
  --argjson checks "$CHECK_CONTEXTS" '
  {
    name: "org-required-quality-gate",
    target: "branch",
    source: "Operation",
    enforcement: "active",       # "evaluate" = dry-run, "active" = enforced
    rules: [
      {
        type: "required_status_checks",
        parameters: {
          strict: true,          # require branch up-to-date before merge
          contexts: $checks
        }
      },
      {
        type: "pull_request",
        parameters: {
          required_approving_review_count: 1,
          dismiss_stale_reviews: true,
          require_code_owner_reviews: false,
          require_last_push_approval: false
        }
      },
      { type: "required_linear_history" },
      { type: "deletion" }
    ],
    conditions: {
      ref_name: {
        include: ["refs/heads/main", "refs/heads/master", "refs/heads/release/*", "refs/heads/develop"],
        exclude: []
      },
      repo_property: [],          # empty = ALL repos; filter via custom properties if needed
      include_all_repositories: true
    }
  }')

echo "Creating org-level ruleset for $ORG (enforcement: active)..."
echo "$payload" | jq .
echo

echo "$payload" | gh api --method POST \
  -H "Accept: application/vnd.github+json" \
  "/orgs/$ORG/rulesets" --input -

echo
echo "Created. Verify:  gh api /orgs/$ORG/rulesets | jq"
echo
echo "To switch to enforced/evaluate toggle:  edit the 'enforcement' field via"
echo "  gh api -X PATCH /orgs/$ORG/rulesets/<id> -f enforcement=evaluate|active"

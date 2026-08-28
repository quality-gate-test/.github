#!/usr/bin/env bash
# bootstrap-ci.sh — add .github/workflows/ci.yml to every org repo listed in repos.tsv.
#
# repos.tsv format (TAB separated):  <repo-name> \t <lang>  \t [extra inputs...]
#   billing-api     node    node-version=20
#   orders-svc      java    build-tool=gradle
#   data-pipeline   python  python-version=3.12
#
# Usage:
#   ORG=quality-gate-test ./bootstrap-ci.sh
# Requires: gh (authed), git, jq.
set -euo pipefail

ORG="${ORG:-quality-gate-test}"
TPL_DIR="$(cd "$(dirname "$0")/.." && pwd)/.github/workflow-templates"
BRANCH="${BRANCH:-ci/add-quality-gate}"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh CLI not found. Install & 'gh auth login' first." >&2; exit 1
fi

[ -f repos.tsv ] || { echo "repos.tsv missing in $(pwd)" >&2; exit 1; }

while IFS=$'\t' read -r repo lang extras; do
  [ -z "${repo:-}" ] && continue
  case "$lang" in
    node|nodejs)   src="$TPL_DIR/node-ci.yml" ;;
    java|maven|gradle) src="$TPL_DIR/java-ci.yml" ;;
    python|py)     src="$TPL_DIR/python-ci.yml" ;;
    *) echo "  skip $repo: unknown lang '$lang'" >&2; continue ;;
  esac

  echo "==> $repo ($lang)"
  tmp="$(mktemp -d)"
  gh repo clone "$ORG/$repo" "$tmp" -- --depth 1 2>/dev/null || { echo "  clone failed, skipping"; continue; }
  mkdir -p "$tmp/.github/workflows"
  cp "$src" "$tmp/.github/workflows/ci.yml"

  # apply extra inputs (key=value) into the with: block
  if [ -n "${extras:-}" ]; then
    for kv in $extras; do
      k="${kv%%=*}"; v="${kv#*=}"
      # replace the default value for key k
      sed -i "s|^\(      ${k}:\).*|\1 ${v}|" "$tmp/.github/workflows/ci.yml"
    done
  fi

  ( cd "$tmp" && \
    git checkout -b "$BRANCH" && \
    git add .github/workflows/ci.yml && \
    git commit -m "ci: add org quality gate ($lang)" -m "Uses reusable workflow from $ORG/.github" && \
    git push -u origin "$BRANCH" && \
    gh pr create --title "ci: add org quality gate" --body "Adds CI via reusable workflow (\`$ORG/.github\`). Required once before org ruleset enforces it." --base main || \
    gh pr create --title "ci: add org quality gate" --body "Adds CI via reusable workflow." )
  rm -rf "$tmp"
done < repos.tsv

echo "Done. Merge the PRs; then run create-ruleset.sh."

# Org shared CI gate

This repo (`quality-gate-test/.github`) is the **central place** that defines code-quality gates
for every repository in the `quality-gate-test` organization. Each service repo references these
reusable workflows — change a gate once here, every repo picks it up on its next CI run.

## Layout

```
.github/workflows/gate-node.yml      # reusable gate for Node.js / TypeScript
.github/workflows/gate-java.yml      # reusable gate for Java (Maven/Gradle)
.github/workflows/gate-python.yml    # reusable gate for Python
.github/workflow-templates/*.yml     # starter ci.yml a repo drops into .github/workflows/
eslint-config/                      # shared ESLint config (publish as @quality-gate-test/eslint-config)
python-config/ruff.toml              # shared ruff/mypy config
scripts/bootstrap-ci.sh             # add ci.yml to every repo (reads repos.tsv)
scripts/create-ruleset.sh           # create org-level ruleset (required checks + PR)
repos.tsv                           # (you create this) repo → lang mapping for bootstrap
```

## One-time setup

1. Create this repo (if it doesn't exist) and push this content:
   ```bash
   cd org-dotgithub
   git init && git add -A && git commit -m "init: org quality gate"
   gh repo create quality-gate-test/.github --public --source=. --push
   ```

2. For each existing repo, add a CI workflow (creates a PR per repo):
   ```bash
   ORG=quality-gate-test ./scripts/bootstrap-ci.sh   # after you write repos.tsv (see below)
   ```
   `repos.tsv` format (TAB-separated):
   ```
   billing-api	node	node-version=20
   orders-svc	java	build-tool=gradle
   data-pipeline	python	python-version=3.12
   ```

3. Merge those PRs and let at least one CI run succeed per repo (so the check
   contexts register with GitHub — required checks only block merges *after* they've run).

4. Turn on enforcement (org-level ruleset):
   ```bash
   ORG=quality-gate-test ./scripts/create-ruleset.sh
   ```
   Start with `enforcement: "evaluate"` (dry-run) if you want to preview before enforcing.

## Required status checks

The ruleset requires these check contexts (job names from the reusable gates):

| Context        | Gate file
|----------------|-----------
| `gate / lint`  | all
| `gate / test`  | all
| `gate / build` | node, java, python(if build enabled)

If a repo legitimately doesn't have `build` (e.g. a library), set `run-build: false`
in its `ci.yml` and remove `gate / build` from that repo's requirements (use a
repo-scoped ruleset for exceptions).

## Why reusable workflows, not per-repo CI?

- **Single source of truth** — fix a flaky linter step once, all repos benefit.
- **No drift** — you can't "forget" to add the gate on a new repo if you also
  use this `.github` repo's starter templates / a template repo.
- **Org-level ruleset** enforces the gate is *required* — dev can't bypass it.

## Troubleshooting

- **"Required check never passes / not found"** — the job name in `contexts` must
  exactly match what GitHub shows in the PR checks UI. Reusable-workflow jobs appear
  as `gate / lint` (the caller job `gate` + called job `lint`). Adjust in
  `create-ruleset.sh` if your caller job is named differently.
- **`workflow_call` not allowed** — in the `.github` repo settings, the workflow
  must be on the default branch; reusable workflows can only be called from the
  default branch ref (`@main`).
- **Check runs as different name** — confirm via `gh api /repos/quality-gate-test/<repo>/commits/<sha>/check-runs`.

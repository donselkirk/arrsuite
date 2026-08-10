# Upstream Integration

ArrSuite tracks reviewed Community Scripts application sources and framework
helpers in `tools/upstream-lock.json`. Reviewed helper copies are stored under
`vendor/community-scripts/misc/` and published with every ArrSuite release.

## Weekly automated review

Every Monday at 09:17 UTC, GitHub Actions compares all locked Community Scripts
sources. Mechanically safe helper changes are copied into the reviewed bundle,
repatched to use ArrSuite's release-pinned helper base, and validated.
Helper-only changes are proposed on the stable `automation/upstream-review`
branch.

The workflow creates or refreshes one merge-ready pull request and assigns it
to `donselkirk`. It never merges or enables auto-merge. Network failures,
unexpected helper layouts, checksum failures, Codex failures, or validation
failures stop before the PR branch is updated and create or refresh one assigned
failure issue with the run report and local Codex repair instructions.

Application install/CT changes are not imported blindly. They are listed in
`upstream-review/pending.md` without advancing their locks. Instead of opening a
competing deterministic PR, the workflow invokes the official Codex GitHub
Action using a repository-owned prompt. Codex
adapts the modules without GitHub credentials in the `workspace-write` sandbox
with `sudo` removed. The workflow then independently verifies the expected
locks, restricts changed paths, regenerates artifacts, runs the full test suite,
and opens a merge-ready PR to `main`. Pull-request validation remains blocked
until the pending file is removed, and only `donselkirk` can manually merge the
result; the automation never merges or enables auto-merge.

The Codex Action requires a repository Actions secret named `OPENAI_API_KEY`.
The key is passed through the action's Responses API proxy and is never exposed
to the later GitHub-authenticated PR step. Keep the action on its default
`drop-sudo` safety strategy and the `workspace-write` sandbox. The normal
workflow `GITHUB_TOKEN` is provided only to the reporting and PR-publishing
steps after Codex and deterministic validation complete. Successful runs do not
create tracking issues.

Failure issues are deduplicated under a stable title and assigned to
`donselkirk`. A later successful run closes the open failure issue automatically.
If local repair is required, use the issue instructions with Codex, open a PR
that closes the issue, and manually squash-merge it after validation.

## Manual read-only check

```bash
bash tools/check-upstream.sh
```

The daily checker compares each locked reference against its recorded repository
and verifies the integrity of the vendored helper copies. Network/query
failures are reported separately from actual source changes.
Production applications are tracked in `community-scripts/ProxmoxVE`; when a
production-tracked path appears in `community-scripts/ProxmoxVED`, the report
also flags it for development-version review. Focused reports are written
under `upstream-report/`.

The read-only command does not modify reviewed files or locks. Workflow reports
and focused diffs are also uploaded as run artifacts.

## Import reviewed behavior

1. Review the automated helper PR or the Codex-created application PR and its
   focused report.
2. For pending application items, verify the relevant `apps/<app>.sh` and
   templates cover the upstream behavior before accepting the updated lock.
3. Confirm helper-base substitutions remain intact and remove
   `upstream-review/pending.md` only after every listed item is resolved.
4. Regenerate and validate:

```bash
bash tools/build-artifacts.sh
bash tests/static-checks.sh
git diff --check
```

This keeps ArrSuite releases reproducible while making upstream changes easier
to identify and integrate.

Production bootstrap and self-update never execute a newly discovered helper
revision automatically. A reviewed PR must be manually merged and released
first. `COMMUNITY_SCRIPTS_URL` remains an explicit development override for
testing live upstream helpers.

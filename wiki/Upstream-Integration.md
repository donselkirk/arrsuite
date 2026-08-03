# Upstream Integration

ArrSuite tracks reviewed Community Scripts application sources and framework
helpers in `tools/upstream-lock.json`. Reviewed helper copies are stored under
`vendor/community-scripts/misc/` and published with every ArrSuite release.

## Check for changes

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

An upstream difference is a review prompt, not an automatic update. Never
execute newly discovered upstream content automatically.

## Import reviewed behavior

1. Review the focused upstream diff.
2. Update the relevant `apps/<app>.sh`, template, or vendored helper. For
   `build.func` and `install.func`, retain the ArrSuite helper-base substitution
   so nested downloads stay on the same release.
3. Update the locked source blob, upstream checksum, and vendored checksum.
4. Regenerate and validate:

```bash
bash tools/build-artifacts.sh
bash tests/static-checks.sh
git diff --check
```

This keeps ArrSuite releases reproducible while making upstream changes easier
to identify and integrate.

Production bootstrap and self-update never execute a newly discovered helper
revision automatically. `COMMUNITY_SCRIPTS_URL` is an explicit development
override for testing live upstream helpers.

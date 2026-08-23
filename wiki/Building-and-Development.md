# Building and Development

Follow `AGENTS.md` for development guardrails, `AI_SPEC.md` for canonical
runtime/compatibility behavior, and `GITHUB_AI_INSTRUCTIONS.md` for
GitHub Copilot coding/review agent expectations.

## Generate artifacts

Editable sources are assembled into the standalone manager and self-contained
installer:

```bash
bash tools/build-artifacts.sh
```

Do not edit `tools/arrsuite-manager` or `install/arrsuite-install.sh` directly.

## Validate

```bash
bash tests/static-checks.sh
git diff --check
```

The suite covers:

- Bash syntax;
- JSON parsing;
- generated artifact synchronization;
- byte-for-byte embedded template checks;
- manager behavior;
- the exact release payload and checksums;
- reviewed helper provenance and local integrity;
- ShellCheck when installed.

Local checks do not prove LXC creation, systemd startup, release downloads, or
web interface availability. Test release-affecting changes on a disposable
Proxmox node.

## Releases

Protected `main` accepts changes only through a manually approved squash merge.
Every resulting push runs GitHub Actions validation. A successful run creates
or verifies exactly one patch release for that commit with an Important Changes
summary, a full comparison link, `SHA256SUMS`, stable runtime assets, and the
reviewed Community Scripts helper bundle. The workflow downloads the published
payload and verifies its checksums before declaring the release complete.

Pull requests run the same validation with read-only repository permissions but
never calculate a version, publish assets, or create a release. Automated
upstream-review PRs with a pending
application marker intentionally fail until the listed semantic adaptations
are completed.

GitHub-hosted runner images change independently of ArrSuite. Workflows that
run the static suite install ShellCheck and ripgrep explicitly so validation
does not depend on incidental tools in a particular weekly runner image.

Post-merge release failures create or refresh one assigned GitHub issue with
the failing commit, run URL, stage results, and local Codex repair guidance.

## Self-update compatibility

`release/COMPATIBILITY` is part of the checksummed public release interface.
Keep `minimum_direct_version` at the oldest version that can safely consume the
current runtime assets. `bridge_version` must identify a retained release that
is at least that new and older than the release being built. Never raise the
minimum in the same release that first becomes incompatible: publish the bridge
first, keep its assets available, and only then ship the gated release.

Every PR that changes the manager, release assets, dependencies, filesystem
layout, helper loading, or update process must explicitly assess skipped-version
upgrades. Update the compatibility metadata and tests when a direct upgrade is
not safe. The updater must fail before modifying local files and provide exact
bridge and follow-up commands.

Managers from before the compatibility contract ignore unknown metadata.
Consequently, current release assets and the manager entry point must remain
safe for the legacy download/install protocol and perform any required migration
themselves. Do not treat a raised minimum alone as protection for those older
installations.

Compatibility claims must be supported by tagged updater code and historical
release instructions. The current historical baseline is v1.0.31, when the
complete checksummed helper bundle became available. Upgrades from v1.0.30 or
older use that release twice because the first pass replaces the manager and
the second installs the full helper bundle. The final command must explicitly
set `ARRSUITE_UPDATE_BASE_URL` to `releases/latest/download`; the old manager
persists a pinned bridge URL in `/opt/arrsuite/update.url`, so a plain follow-up
can incorrectly report that v1.0.31 is current. Versions before v1.0.29 must also
override `COMMUNITY_SCRIPTS_URL` to the active `ProxmoxVE` repository on the
first pass because their manager defaults to the retired `ProxmoxVED` path.

The Markdown files under `wiki/` are the canonical Wiki sources. Changes to
them on `main` are published automatically by `.github/workflows/wiki.yml`;
avoid editing the published GitHub Wiki separately.

## Install a specific release

Version-pinned installation is intended for development and regression
testing. Use the same release base URL for the bootstrap and all assets:

```bash
export ARRSUITE_RELEASE_BASE_URL="https://github.com/donselkirk/arrsuite/releases/download/<version>"
bash -c "$(curl -fsSL "${ARRSUITE_RELEASE_BASE_URL}/arrsuite.sh")"
```

## Adding an application

Create `apps/<app>.sh` and its systemd template, then update:

- supported application arrays and maps;
- labels, description, port, and architecture behavior;
- install, update, and dispatch cases;
- initial checklist and help output;
- login banner and CT completion output;
- JSON metadata, documentation, and tests.
- reviewed install and update blobs in `tools/upstream-lock.json`.

Base behavior on the current individual Community Scripts implementation.

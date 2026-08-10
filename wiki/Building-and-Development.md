# Building and Development

Follow the repository's `AGENTS.md` instructions for all changes.

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

Post-merge release failures create or refresh one assigned GitHub issue with
the failing commit, run URL, stage results, and local Codex repair guidance.

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

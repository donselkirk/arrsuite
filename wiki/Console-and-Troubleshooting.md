# Console and Troubleshooting

When the LXC root password is blank, ArrSuite configures automatic root login
for:

| Service | Console |
|---|---|
| `container-getty@1.service` | Proxmox web UI on `/dev/tty1` |
| `console-getty.service` | `pct console` on `/dev/console` |

The Debian 13 overrides clear inherited credential imports using an empty
`ImportCredential=` directive. Removing it can cause `243/CREDENTIALS` in an
unprivileged LXC.

## Repair a blank console

Enter the container from the Proxmox host:

```bash
pct enter <CTID>
```

Then run:

```bash
curl -fsSL https://github.com/donselkirk/arrsuite/releases/latest/download/fix-console-autologin.sh | bash
```

## Useful diagnostics

```bash
arrsuite list
arrsuite status
systemctl status container-getty@1.service
systemctl status console-getty.service
journalctl -u <app>.service --no-pager
df -h
```

Application-targeted commands fail cleanly when the requested application is
not installed and show the corresponding `arrsuite add <app>` command.

## GitHub API rate limit during an update

ArrSuite checks GitHub releases separately for each installed app. Anonymous
API requests share a limit per public IP address, so several apps can report
the same rate-limit error during one update. [GitHub API rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)

Retry after the rate limit resets, or run the update from a root Bash shell
inside the LXC with a personal access token for public read access. The prompt
hides the token and the subshell keeps it scoped to this update.

```bash
(
  IFS= read -rsp 'GitHub token: ' GITHUB_TOKEN || exit
  printf '\n'
  export GITHUB_TOKEN
  update
)
```

# gitea-github-sync

Mirrors all GitHub repositories owned by a configured user into Gitea as pull mirrors. Runs as a oneshot container on a systemd timer every 6 hours.

## How it works

1. A Python script (stdlib only, no pip dependencies) calls the GitHub API to list all owned repos
2. It calls the Gitea API to list existing mirrors
3. For new repos, it calls the Gitea migrate API to create a pull mirror
4. Gitea then polls GitHub every `mirror_interval` to sync changes
5. The timer re-runs the script to catch any newly created GitHub repos

The script is **idempotent**: repos that already exist in Gitea are silently skipped.

## Prerequisites

- Gitea must be running (`gitea.service` active)
- A Gitea admin user account must exist (created via the install wizard or registration)

## Required secrets (Ansible Vault)

| Variable | Description |
|---|---|
| `vault_gitea_sync_github_token` | GitHub Personal Access Token with `repo` scope |
| `vault_gitea_sync_gitea_token` | Gitea API token (generated in user settings) |

### Creating the GitHub token

1. Go to https://github.com/settings/tokens → **Generate new token (classic)**
2. Scopes: ✅ `repo` (required for private repos)
3. Add to vault as `vault_gitea_sync_github_token`

### Creating the Gitea token

1. Log into Gitea → User Settings → Applications
2. Generate a token named `gitea-mirror-sync`
3. Add to vault as `vault_gitea_sync_gitea_token`

## Key variables

| Variable | Default | Description |
|---|---|---|
| `gitea_sync_github_user` | `""` | GitHub username whose repos to mirror |
| `gitea_sync_gitea_url` | `http://localhost:3000` | Gitea base URL |
| `gitea_sync_mirror_interval` | `6h0m0s` | How often Gitea polls GitHub for updates |
| `gitea_sync_timer_oncalendar` | `*-*-* 00,06,12,18:00:00` | When to check for new repos |
| `gitea_sync_image` | `docker.io/library/python:3.13-alpine3.21` | Container image |

All variables are defined in `defaults/main.yml`. Override in `inventory/group_vars/relay_services/gitea-github-sync.yml`.

## Deployment

```bash
ansible-playbook site.yml --tags gitea-github-sync --ask-vault-pass
```

## Operations

```bash
# Check timer
systemctl list-timers gitea-github-sync.timer

# Run sync immediately (discovers new repos)
systemctl start gitea-github-sync.service

# View sync logs
journalctl -u gitea-github-sync.service -f

# View Gitea mirror status
# Gitea web UI → any repo → Settings → Mirror Settings → Last Sync
```

## Mirror privacy

Mirrored repos match the privacy of the source GitHub repo: private repos are private on Gitea, public repos are public.

## Handling fork/archived repos

The sync includes all repos returned by `GET /user/repos?type=owner&affiliation=owner`. This excludes repos you have access to but do not own (forks of others' repos). Your own forks are included.

To exclude specific repos, Gitea's pull mirrors can be deleted via the Gitea web UI and will not be recreated unless you modify the script.

# gitea-github-sync

Mirrors all GitHub repositories owned by a configured user into Gitea as pull mirrors. Runs as a oneshot Python container on a systemd timer every 6 hours.

## How it works

1. A Python script (stdlib only, no pip dependencies) calls the GitHub API to list all owned repos
2. It calls the Gitea API to list existing mirrors
3. For new repos, it calls the Gitea migrate API to create a pull mirror
4. Gitea then polls GitHub on the configured `mirror_interval` to sync changes
5. The timer re-runs the script periodically to pick up any newly created GitHub repos

The script is **idempotent**: repos that already exist in Gitea are silently skipped.

## Full rebuild procedure

Follow this sequence exactly when deploying from scratch.

### Step 1 — Deploy Gitea

```bash
ansible-playbook site.yml --tags gitea --ask-vault-pass
```

### Step 2 — Complete the Gitea install wizard

Navigate to `http://<nas-ip>:3000` in a browser.

Accept all defaults **except**:
- **Administrator Account Settings** (at the bottom): fill in a username, email, and password to create the admin account.

Click **Install Gitea**.

> ⚠️ If you skip the administrator section, the first user to register after install becomes admin. That is fine — but you must register immediately before anyone else does.

### Step 3 — Create a GitHub Personal Access Token

1. Go to https://github.com/settings/tokens → **Generate new token (classic)**
2. Name: `gitea-mirror-sync`
3. Scopes: ✅ `repo` (full repo access — required for private repos)
4. Click **Generate token** and copy the value

### Step 4 — Create a Gitea API token

1. Log into Gitea → click your avatar → **Settings** → **Applications**
2. Under **Manage Access Tokens**, enter token name: `gitea-mirror-sync`
3. Select scopes:
   - **Repository**: ✅ Read + Write (required to create mirrors)
   - **User**: ✅ Read (required to look up user ID)
4. Click **Generate Token** and copy the value

> ⚠️ **Scopes are required.** A Gitea token with no scopes selected returns HTTP 403. A token with only some scopes returns HTTP 403 for the missing ones. Select exactly the scopes listed above.

### Step 5 — Add tokens to Ansible Vault

```bash
# Decrypt, append, re-encrypt
cd /path/to/relay
DECRYPTED=$(ansible-vault view inventory/group_vars/relay_services/vault.yml --ask-vault-pass)
printf '%s\nvault_gitea_sync_github_token: "%s"\nvault_gitea_sync_gitea_token: "%s"\n' \
  "$DECRYPTED" "<GITHUB_TOKEN>" "<GITEA_TOKEN>" \
  | ansible-vault encrypt --ask-vault-pass \
      --output inventory/group_vars/relay_services/vault.yml
```

### Step 6 — Deploy the sync role

```bash
ansible-playbook site.yml --tags gitea-github-sync --ask-vault-pass
```

### Step 7 — Trigger the first sync

```bash
# On the NAS:
sudo systemctl start gitea-github-sync.service
sudo journalctl -u gitea-github-sync.service -f
```

Expected output:
```
Gitea: authenticated as 'admin' (uid=1)
GitHub: fetching repos for 'philbudden'...
GitHub: found 42 owned repos
Gitea:  0 repos already mirrored
  CREATE relay (private)
  CREATE keystone (private)
  ...
Done: 42 created, 0 skipped, 0 errors
```

---

## Required secrets (Ansible Vault)

| Variable | Description |
|---|---|
| `vault_gitea_sync_github_token` | GitHub Personal Access Token (`repo` scope) |
| `vault_gitea_sync_gitea_token` | Gitea API token (Repository Read+Write, User Read) |

---

## Key variables

| Variable | Default | Description |
|---|---|---|
| `gitea_sync_github_user` | `""` | GitHub username whose repos to mirror |
| `gitea_sync_gitea_url` | `http://localhost:3000` | Gitea base URL |
| `gitea_sync_mirror_interval` | `6h0m0s` | How often Gitea polls GitHub for updates |
| `gitea_sync_timer_oncalendar` | `*-*-* 00,06,12,18:00:00` | When to discover new repos (00:00, 06:00, 12:00, 18:00 UTC) |
| `gitea_sync_image` | `docker.io/library/python:3.13-alpine3.21` | Container image |

Override in `inventory/group_vars/relay_services/gitea-github-sync.yml`.

---

## Operations

```bash
# Check timer schedule
systemctl list-timers gitea-github-sync.timer

# Run sync immediately (e.g. after creating a new GitHub repo)
sudo systemctl start gitea-github-sync.service

# View sync logs
journalctl -u gitea-github-sync.service -f

# Check Gitea mirror sync status
# Gitea web UI → any repo → Settings → Mirror Settings → Last sync time
```

---

## Mirror behaviour

- **Privacy**: mirrors match GitHub visibility — private repos are private on Gitea, public repos are public
- **Scope**: only repos you *own* (`affiliation=owner`) — not repos you collaborate on
- **Your forks**: included (you own them)
- **Archived repos**: included (mirrored as-is)
- **Exclusions**: delete a mirror in the Gitea web UI — it will not be recreated automatically

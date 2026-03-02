# Gitea Role

Self-hosted Git remote service running as a Podman container via Quadlet.

## Overview

This role deploys [Gitea](https://about.gitea.com) — a lightweight, self-hosted Git service. It provides a web UI, HTTP and SSH Git remotes, issue tracking, and pull requests without requiring external services.

## Prerequisites

**Required (provided by Keystone):**
- Podman installed and configured
- SSD storage mounted at `/mnt/ssd`
- Quadlet directory: `/etc/containers/systemd`
- systemd as init system

**Required (manual or via Keystone):**
- Firewall rules for Gitea:
  - TCP 3000 (HTTP web UI and Git-over-HTTP)
  - TCP 2222 (Git-over-SSH — avoids conflict with host SSH on port 22)

**Note**: Firewall configuration is **out of scope** for Relay. Configure in Keystone or manually.

## Architecture

```
┌───────────────────────────────────────────┐
│              Gitea Container              │
│                                           │
│  Port 3000: Web UI / HTTP Git             │
│  Port 2222: SSH Git                       │
│  Image: docker.io/gitea/gitea:1.23.7     │
└───────────────────────────────────────────┘
                     │
                     ▼
        /mnt/ssd/services/gitea/data
        (repositories, config, DB)
```

## Default Configuration

| Setting | Default | Description |
|---------|---------|-------------|
| HTTP port | `3000` | Web UI and HTTP Git operations |
| SSH port | `2222` | SSH Git operations |
| Data dir | `/mnt/ssd/services/gitea/data` | All persistent data |
| App name | `Gitea` | Display name in UI |
| Domain | `` (empty) | Set to NAS hostname/IP |

## Usage

### Basic Deployment

```yaml
# inventory/group_vars/relay_services/gitea.yml
gitea_domain: "nas.local"
```

Run playbook:

```bash
ansible-playbook site.yml --tags gitea
```

### First-Time Setup

After deploying, open the web UI at `http://<nas-ip>:3000` to complete the initial configuration wizard. You can set:
- Administrator account
- Email settings
- Additional repository options

Settings configured via environment variables (e.g. `gitea_domain`) take effect at container start and pre-populate the installer.

### Custom Configuration

Override defaults in inventory:

```yaml
# inventory/group_vars/relay_services/gitea.yml
gitea_domain: "git.home.arpa"
gitea_http_port: 3000
gitea_ssh_port: 2222
gitea_app_name: "HomeNAS Git"
gitea_timezone: "Europe/London"
```

## Variables

### Image Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `gitea_image` | `docker.io/gitea/gitea` | Container image |
| `gitea_image_tag` | `1.23.7` | Image tag — pin for production |
| `gitea_use_digest` | `false` | Use digest pinning |
| `gitea_image_digest` | `""` | Image digest (if enabled) |

### Storage

| Variable | Default | Description |
|----------|---------|-------------|
| `gitea_base_dir` | `{{ relay_storage_root }}/gitea` | Base directory |
| `gitea_data_dir` | `{{ gitea_base_dir }}/data` | Repositories and config |

### Network

| Variable | Default | Description |
|----------|---------|-------------|
| `gitea_http_port` | `3000` | HTTP/web port on host |
| `gitea_ssh_port` | `2222` | SSH port on host |
| `gitea_domain` | `""` | Hostname or IP for URL generation |

### Application

| Variable | Default | Description |
|----------|---------|-------------|
| `gitea_app_name` | `Gitea` | UI display name |
| `gitea_timezone` | `UTC` | Container timezone |
| `gitea_run_uid` | `1000` | UID to run container process as |
| `gitea_run_gid` | `1000` | GID to run container process as |

## Accessing Gitea

### Web UI

```
http://<nas-ip>:3000
```

### Clone via HTTP

```bash
git clone http://<nas-ip>:3000/<user>/<repo>.git
```

### Clone via SSH

SSH uses port 2222 to avoid conflict with the host SSH daemon. Configure `~/.ssh/config`:

```
Host nas-git
    HostName <nas-ip>
    Port 2222
    User git
```

Then clone:

```bash
git clone git@nas-git:<user>/<repo>.git
```

## Upgrading Gitea

1. **Check release notes** — visit https://github.com/go-gitea/gitea/releases for breaking changes

2. **Update image tag**:
   ```yaml
   # roles/gitea/defaults/main.yml or inventory override
   gitea_image_tag: "1.24.0"
   ```

3. **Test in check mode**:
   ```bash
   ansible-playbook site.yml --tags gitea --check --diff
   ```

4. **Deploy**:
   ```bash
   ansible-playbook site.yml --tags gitea
   ```

5. **Verify service started**:
   ```bash
   systemctl status gitea.service
   journalctl -u gitea.service -n 50 --no-pager
   ```

6. **Rollback if needed**:
   ```bash
   git revert HEAD
   ansible-playbook site.yml --tags gitea
   ```

## Operations

### Check Service Status

```bash
systemctl status gitea.service
```

### View Logs

```bash
journalctl -u gitea.service -f
```

### Restart Service

```bash
systemctl restart gitea.service
```

### Check Container

```bash
podman ps | grep gitea
podman logs gitea
```

## Troubleshooting

### Web UI not accessible

```bash
# Check service is running
systemctl status gitea.service

# Check port is listening
ss -tlnp | grep 3000

# Check container logs
podman logs gitea
```

### SSH clone fails

- Verify SSH port `2222` is open in the firewall (Keystone responsibility).
- Check `~/.ssh/config` uses `Port 2222`.

### Data not persisting

Verify the data volume is mounted:

```bash
podman inspect gitea | grep -A5 Mounts
```

Ensure `{{ gitea_data_dir }}` exists on the host with correct permissions.

## Security Considerations

1. **Restrict access to trusted networks** — expose ports only via Tailscale/VPN
2. **Register an admin account immediately** after first-time setup to prevent open registration
3. **Disable open registration** in Gitea admin panel once your users are created
4. **Pin image versions** — avoid `latest` in production
5. **Regular updates** — keep Gitea image updated for security patches

## Migration Notes (Debian → Fedora IoT)

This role is OS-agnostic and requires no changes for Fedora IoT migration:

- ✅ Uses Podman/Quadlet (portable)
- ✅ No OS-specific packages required
- ✅ No Debian-specific paths or tools
- ✅ Container handles all Gitea dependencies

## References

- [Gitea documentation](https://docs.gitea.com)
- [Gitea container image](https://hub.docker.com/r/gitea/gitea)
- [Podman Quadlet documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)

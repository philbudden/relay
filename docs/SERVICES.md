# Relay Service Catalog

Comprehensive list of containerized services managed by Relay.

## Currently Implemented

### Samba (SMB/CIFS File Sharing)

**Status**: ✅ Implemented  
**Role**: `roles/samba`  
**Documentation**: [roles/samba/README.md](../roles/samba/README.md)

Exposes NAS storage via SMB/CIFS protocol for network file sharing.

**Features**:
- Multi-user authentication
- Configurable shares (read-write or read-only)
- Exposes SSD and backup storage
- Windows/macOS/Linux compatible

**Default Shares**:
- `ssd` - Read-write storage on `/mnt/ssd/shares`
- `backup` - Read-only storage on `/mnt/backup/shares`

**Access**:
- Windows: `\\<nas-ip>\ssd`
- macOS/Linux: `smb://<nas-ip>/ssd`

**Tags**: `samba`, `file-sharing`

---

### Gitea GitHub Mirror Sync

**Status**: ✅ Implemented
**Role**: `roles/gitea-github-sync`
**Documentation**: [roles/gitea-github-sync/README.md](../roles/gitea-github-sync/README.md)

Automatically mirrors all GitHub repos owned by the configured user into Gitea as pull mirrors.

**Features**:
- Discovers all owned GitHub repos (public and private) and creates Gitea pull mirrors
- Idempotent — skips repos already mirrored
- Privacy-preserving — private GitHub repos stay private in Gitea
- Timer-driven — runs every 6 hours to pick up newly created repos
- Stdlib-only Python script, no pip dependencies

**Tags**: `gitea-github-sync`, `gitea`, `git`

> ⚠️ **Rebuild note**: Gitea API tokens require explicit scope selection. See the role README for the full step-by-step rebuild procedure including required token scopes.

---

### NVR (RTSP Camera Recording)

**Status**: ✅ Implemented  
**Role**: `roles/nvr`  
**Documentation**: [roles/nvr/README.md](../roles/nvr/README.md)

Declarative 24/7 RTSP camera recording with daily archival and rolling retention.

**Features**:
- Records multiple cameras simultaneously (one container per camera)
- 5-minute segment files for resilience
- Daily concatenation at 01:00 UTC into single 24-hour files
- Automatic deletion of segments after successful concatenation
- Rolling retention window (default 30 days)
- RTSP credentials secured via Ansible Vault + host secrets files
- No web UI, no motion detection, no database

**Storage**:
- Segments: `/mnt/ssd/services/nvr/cameras/[name]/segments/YYYY-MM-DD/`
- Daily recordings: `/mnt/ssd/services/nvr/cameras/[name]/daily/YYYY-MM-DD.mp4`

**Tags**: `nvr`, `cameras`, `recording`

---

### Gitea (Self-Hosted Git Remote)

**Status**: ✅ Implemented  
**Role**: `roles/gitea`  
**Documentation**: [roles/gitea/README.md](../roles/gitea/README.md)

Lightweight, self-hosted Git service with web UI, HTTP and SSH remotes, issue tracking, and pull requests.

**Features**:
- Web UI for repository management
- HTTP and SSH Git remotes
- Issue tracking and pull requests
- Repositories persist on SSD storage

**Storage**:
- Data (repos, config, DB): `/mnt/ssd/services/gitea/data`

**Ports**:
- `3000/tcp` — Web UI and HTTP Git
- `2222/tcp` — SSH Git (avoids conflict with host SSH on 22)

**Tags**: `gitea`, `git`

---

## Planned Services

### Restic (Backup Service)

**Status**: 🎯 Planned  
**Purpose**: Encrypted incremental backups

**Features**:
- Deduplication
- Encryption
- Multiple backend support (B2, S3, local)

---

## Service Selection Criteria

Services are added to Relay when they meet these criteria:

### ✅ Include If

1. **Runs in container** - No native system packages required
2. **Well-maintained image** - Official or trusted community image
3. **Documented** - Clear configuration and usage docs
4. **Stateless or data-isolated** - Data stored on persistent volumes
5. **Service-level concern** - Not a host-level responsibility

### ❌ Exclude If

1. **Requires host packages** - Belongs in Keystone
2. **Modifies kernel/system** - Belongs in Keystone
3. **Requires privileged access** - Security risk (exception: Cockpit in Keystone)
4. **Poorly maintained** - No recent updates, security issues
5. **Better as native service** - e.g., SSH, systemd-resolved

---

## Adding a New Service

Follow this workflow:

### 1. Research

- [ ] Identify official or trusted container image
- [ ] Review image documentation
- [ ] Check security track record
- [ ] Verify active maintenance

### 2. Design

- [ ] Define storage requirements (volumes, paths)
- [ ] Plan network exposure (ports, protocols)
- [ ] Identify secrets (passwords, keys)
- [ ] Document dependencies

### 3. Implement

- [ ] Create role: `roles/[service-name]/`
- [ ] Write defaults: `defaults/main.yml`
- [ ] Write tasks: `tasks/main.yml` (idempotent)
- [ ] Create Quadlet template: `templates/[service].container.j2`
- [ ] Define handlers: `handlers/main.yml`
- [ ] Document: `roles/[service-name]/README.md`

### 4. Test

- [ ] Syntax check: `ansible-playbook site.yml --syntax-check`
- [ ] Dry run: `ansible-playbook site.yml --tags [service] --check`
- [ ] Idempotency: Run twice, verify no changes on second run
- [ ] Manual verification: Check service status, logs, functionality

### 5. Document

- [ ] Update this file (SERVICES.md)
- [ ] Update main README.md
- [ ] Write role-specific README

### 6. Commit

Use semantic commits:

```
feat(jellyfin): Add Jellyfin media server role

- Create Quadlet container definition
- Configure storage for media libraries
- Add multi-user support
- Document port requirements (8096/tcp)

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

---

## Service Architecture Patterns

### Storage Patterns

**Configuration** (small, frequently changed):
```
/mnt/ssd/services/[service-name]/config
```

**Data** (large, frequently written):
```
/mnt/ssd/services/[service-name]/data
```

**Media** (large, infrequently changed):
```
/mnt/ssd/media/[type]  # e.g., movies, music, photos
```

**Backups** (large, write-once):
```
/mnt/backup/[service-name]
```

### Network Patterns

**Tailscale-only** (recommended):
```ini
[Container]
Network=host
# Firewall restricts to Tailscale (Keystone)
```

**Custom network** (isolated):
```ini
[Container]
Network=[network-name].network
PublishPort=8080:8080
```

**Host network** (for services requiring it):
```ini
[Container]
Network=host
```

### Security Patterns

**User/Group mapping**:
```ini
[Container]
User=1000:1000  # Map to host user
```

**Read-only root**:
```ini
[Container]
ReadOnly=true
Volume=/tmp:/tmp:rw
```

**Drop capabilities**:
```ini
[Container]
DropCapability=ALL
AddCapability=CAP_NET_BIND_SERVICE  # Only what's needed
```

### Update Patterns

**Manual updates** (default, safer):
```yaml
[service]_image_tag: "2024.01.15"  # Pin to specific version
```

**Auto-updates** (opt-in per service):
```ini
[Container]
AutoUpdate=registry
```

Then run: `podman auto-update`

---

## Service Status Legend

- ✅ **Implemented** - Production-ready, documented, tested
- 🚧 **In Progress** - Under development
- 🎯 **Planned** - Scheduled for implementation
- 💡 **Proposed** - Idea/research phase
- ❌ **Rejected** - Not suitable for Relay

---

## Questions?

- **Scope questions**: Read [AGENTS.md](../AGENTS.md)
- **Service-specific**: See `roles/[service-name]/README.md`
- **Host prerequisites**: See [Keystone README](../keystone/README.md)

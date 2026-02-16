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

## Planned Services

### NFS (Network File System)

**Status**: 🎯 Planned  
**Purpose**: Linux-native file sharing with better performance than SMB

**Rationale**: Faster than Samba for Linux-to-Linux file sharing

---

### Jellyfin (Media Server)

**Status**: 🎯 Planned  
**Purpose**: Media library management and streaming

**Features**:
- Video/music/photo library
- Transcoding support
- Multi-user profiles
- Mobile apps

---

### Nextcloud (Personal Cloud)

**Status**: 🎯 Planned  
**Purpose**: File sync, calendar, contacts, and collaboration

**Features**:
- Dropbox-like file sync
- Calendar and contacts
- Document collaboration
- Mobile apps

---

### Syncthing (P2P File Sync)

**Status**: 🎯 Planned  
**Purpose**: Decentralized file synchronization

**Rationale**: No cloud intermediary, privacy-focused

---

### Restic (Backup Service)

**Status**: 🎯 Planned  
**Purpose**: Encrypted incremental backups

**Features**:
- Deduplication
- Encryption
- Multiple backend support (B2, S3, local)

---

### Home Assistant (Home Automation)

**Status**: 🎯 Planned  
**Purpose**: Smart home automation hub

**Features**:
- Device integration
- Automation rules
- Energy monitoring

---

### Grafana + Prometheus (Monitoring)

**Status**: 🎯 Planned  
**Purpose**: System and service monitoring

**Components**:
- Prometheus (metrics collection)
- Grafana (visualization)
- Node Exporter (system metrics)
- cAdvisor (container metrics)

---

### PostgreSQL (Database)

**Status**: 🎯 Planned  
**Purpose**: Relational database for services

**Use Cases**:
- Nextcloud backend
- Home Assistant database
- Custom applications

---

### Redis (Cache)

**Status**: 🎯 Planned  
**Purpose**: In-memory cache and message broker

**Use Cases**:
- Nextcloud caching
- Session storage
- Rate limiting

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

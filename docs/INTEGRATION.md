# Keystone/Relay Integration Guide

This document clarifies the boundary between Keystone (host provisioning) and Relay (service management).

## Architectural Boundary

```
┌─────────────────────────────────────────────────────────────┐
│                         KEYSTONE                            │
│                   (Host Provisioning)                       │
│                                                             │
│  ✓ OS packages and configuration                           │
│  ✓ Storage primitives (RAID, filesystems, mount units)     │
│  ✓ Podman installation and storage configuration           │
│  ✓ Quadlet directory creation                              │
│  ✓ Tailscale VPN client                                    │
│  ✓ Firewall rules                                          │
│  ✓ Host-level infrastructure (Cockpit)                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ Provides substrate
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                          RELAY                              │
│                   (Service Management)                      │
│                                                             │
│  ✓ Service container definitions (Quadlets)                │
│  ✓ Application configuration                               │
│  ✓ Volume mappings to storage                              │
│  ✓ Service-specific directories                            │
│  ✓ Container image version management                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Keystone Guarantees

When Keystone has successfully run, Relay can assume:

### 1. Container Runtime

- ✅ Podman installed (via `podman` package)
- ✅ Podman socket enabled (`podman.socket`)
- ✅ Container storage configured on SSD: `/mnt/ssd/podman`
- ✅ Quadlet directory exists: `/etc/containers/systemd`
- ✅ `podman-systemd-generator` available

### 2. Storage Primitives

- ✅ SSD mounted at: `/mnt/ssd`
  - Filesystem: XFS
  - Label: `keystone-ssd`
  - systemd mount unit: `mnt-ssd.mount`
  - Writable, sufficient space for containers

- ✅ Backup RAID mounted at: `/mnt/backup`
  - Filesystem: ext4
  - Label: `keystone-backup`
  - systemd mount unit: `mnt-backup.mount`
  - RAID1 across two HDDs

### 3. System Configuration

- ✅ systemd as PID 1
- ✅ Multi-user.target active
- ✅ Network connectivity (Ethernet/WiFi)
- ✅ Tailscale VPN client installed and running (optional but recommended)

### 4. Firewall Configuration

- ✅ Firewall installed and active (firewalld on Fedora, nftables on Debian)
- ✅ Tailnet-only access enforced (if Tailscale configured)
- ⚠️ **Service-specific ports NOT opened by default**

## Relay Responsibilities

Relay must **not** duplicate Keystone's work, but **may**:

### ✅ Allowed

1. **Create directories under managed mounts**
   ```yaml
   - name: Create service directory
     ansible.builtin.file:
       path: /mnt/ssd/services/samba/config
       state: directory
   ```

2. **Set ownership/permissions on service directories**
   ```yaml
   - name: Set directory permissions
     ansible.builtin.file:
       path: /mnt/ssd/services/samba/data
       owner: root
       group: root
       mode: '0755'
   ```

3. **Deploy Quadlet files**
   ```yaml
   - name: Deploy Quadlet
     ansible.builtin.template:
       src: samba.container.j2
       dest: /etc/containers/systemd/samba.container
   ```

4. **Trigger systemd daemon-reload**
   ```yaml
   - name: Reload systemd
     ansible.builtin.systemd:
       daemon_reload: true
   ```

5. **Enable/start systemd units**
   ```yaml
   - name: Start service
     ansible.builtin.systemd:
       name: samba.service
       state: started
       enabled: true
   ```

### ❌ Forbidden

1. **Install OS packages**
   ```yaml
   # BAD - belongs in Keystone
   - ansible.builtin.package:
       name: samba
   ```

2. **Modify firewall rules**
   ```yaml
   # BAD - belongs in Keystone
   - ansible.posix.firewalld:
       port: 445/tcp
   ```

3. **Create mount units**
   ```yaml
   # BAD - belongs in Keystone
   - ansible.builtin.template:
       src: mnt-data.mount.j2
       dest: /etc/systemd/system/mnt-data.mount
   ```

4. **Configure Podman storage**
   ```yaml
   # BAD - belongs in Keystone
   - ansible.builtin.template:
       src: storage.conf.j2
       dest: /etc/containers/storage.conf
   ```

5. **Modify system-level config**
   ```yaml
   # BAD - belongs in Keystone
   - ansible.builtin.sysctl:
       name: net.ipv4.ip_forward
       value: 1
   ```

## Prerequisite Checking Pattern

Every Relay role **must** validate Keystone prerequisites:

```yaml
# roles/[service]/tasks/main.yml

- name: Verify Keystone prerequisites
  ansible.builtin.stat:
    path: "{{ item }}"
  register: prereq_check
  loop:
    - /mnt/ssd
    - /mnt/backup
    - /etc/containers/systemd

- name: Assert prerequisites
  ansible.builtin.assert:
    that:
      - prereq_check.results | selectattr('stat.exists') | list | length == 3
    fail_msg: "Keystone prerequisites not found. Run Keystone playbook first."
    success_msg: "Keystone prerequisites satisfied"
```

This ensures:
- **Fail fast** - Clear error if Keystone hasn't run
- **Explicit dependencies** - Documents what Relay needs
- **Debugging aid** - User knows exactly what's missing

## Firewall Coordination

### Current State

**Keystone manages**:
- Base firewall policy (default deny, Tailnet allow)
- SSH access restrictions
- Cockpit port (9090/tcp)

**Relay documents**:
- Required ports per service (in role README)
- Security implications
- Testing procedures

### Decision Points

You have three options for service ports:

#### Option 1: Manual Configuration (Current)

**Pros**: Clean separation, explicit, user control  
**Cons**: Extra step after Relay deployment

```bash
# After deploying Samba via Relay
sudo firewall-cmd --add-port=445/tcp --permanent
sudo firewall-cmd --add-port=139/tcp --permanent
sudo firewall-cmd --reload
```

#### Option 2: Add to Keystone

**Pros**: Fully automated, one-step deployment  
**Cons**: Keystone needs to know about services (coupling)

```yaml
# keystone/inventory/group_vars/keystone_hosts/firewall.yml
firewall_service_ports:
  - 9090/tcp  # Cockpit
  - 445/tcp   # Samba
  - 139/tcp   # Samba NetBIOS
```

#### Option 3: Firewall Role in Relay (Not Recommended)

**Pros**: Automated with service  
**Cons**: Violates AGENTS.md boundary, duplicates Keystone responsibility

**Current recommendation**: **Option 1** (manual) with clear documentation, moving to **Option 2** if friction becomes significant.

## Service-Specific Prerequisites

### Samba

**Keystone provides**:
- ✅ `/mnt/ssd` mount (writable)
- ✅ `/mnt/backup` mount (writable, but Samba enforces read-only)
- ✅ Podman and Quadlet

**Manual step required**:
- ⚠️ Firewall: TCP 445, 139 (see role README)

**Relay creates**:
- `/mnt/ssd/services/samba/config`
- `/mnt/ssd/services/samba/cache`
- `/mnt/ssd/shares` (share directory)
- `/mnt/backup/shares` (share directory)
- `/etc/containers/systemd/samba.container`

### Future Services

Document here as services are added:

#### NFS (Planned)
**Keystone provides**: Same as Samba  
**Manual step**: Firewall: TCP 2049  
**Relay creates**: `/mnt/ssd/services/nfs/exports`, Quadlet

#### Jellyfin (Planned)
**Keystone provides**: Same as Samba  
**Manual step**: Firewall: TCP 8096  
**Relay creates**: `/mnt/ssd/services/jellyfin/{config,cache}`, media library mappings

## Deployment Sequence

Correct order of operations:

### 1. Initial Setup

```bash
# Step 1: Provision host (Keystone)
cd /opt/keystone
ansible-playbook site.yml

# Verify Keystone success
ujust storage-health
systemctl status podman.socket
ls -la /mnt/ssd /mnt/backup

# Step 2: Deploy services (Relay)
cd /opt/relay
ansible-playbook site.yml

# Step 3: Manual firewall configuration (if needed)
# See service role README for required ports
```

### 2. Adding a Service

```bash
# Relay only - Keystone already provides substrate
cd /opt/relay
ansible-playbook site.yml --tags [new-service]

# Configure firewall if needed
sudo firewall-cmd --add-port=[port]/tcp --permanent
sudo firewall-cmd --reload
```

### 3. Updating Services

```bash
# Update configuration in Git
vim inventory/group_vars/relay_services/[service].yml

# Apply changes
cd /opt/relay
ansible-playbook site.yml --tags [service]

# No Keystone changes needed
```

## Troubleshooting Boundary Issues

### "Keystone prerequisites not found"

**Symptom**: Relay playbook fails with assertion error

**Cause**: Keystone hasn't run or failed

**Solution**:
```bash
cd /opt/keystone
ansible-playbook site.yml

# Verify mounts
mount | grep -E 'mnt/(ssd|backup)'

# Verify Quadlet directory
ls -la /etc/containers/systemd
```

### "Firewall blocking service"

**Symptom**: Cannot connect to service from network

**Cause**: Port not opened (expected, manual step)

**Solution**:
```bash
# Check listening ports
sudo ss -tlnp | grep [port]

# If service is listening but clients can't connect:
sudo firewall-cmd --add-port=[port]/tcp --permanent
sudo firewall-cmd --reload
```

### "Permission denied on /mnt/ssd"

**Symptom**: Container can't write to mounted volume

**Cause**: Incorrect directory ownership/permissions

**Solution**:
```bash
# Check ownership
ls -la /mnt/ssd/services/[service]

# Fix if needed (Relay can do this)
sudo chown -R root:root /mnt/ssd/services/[service]
sudo chmod -R 755 /mnt/ssd/services/[service]
```

### "Podman not found"

**Symptom**: `podman: command not found`

**Cause**: Keystone container-runtime role didn't run

**Solution**:
```bash
cd /opt/keystone
ansible-playbook site.yml --tags containers
```

## FAQ

### Q: Can Relay install system packages if a service needs them?

**A**: No. System packages belong in Keystone. If a service has host dependencies, either:
1. Run it in a container with dependencies included
2. Add the dependency to Keystone and document it

### Q: Can Relay create a new filesystem or mount?

**A**: No. All storage provisioning is Keystone's responsibility. Relay uses existing mounts.

### Q: Can Relay modify firewall rules?

**A**: No. Firewall is host-level security (Keystone). Document required ports in service README.

### Q: Can Relay restart Podman or systemd?

**A**: Relay can:
- ✅ `systemctl daemon-reload` (to load new Quadlets)
- ✅ `systemctl restart [service].service` (service-specific)
- ❌ `systemctl restart podman.socket` (host-level)
- ❌ `systemctl restart systemd-*` (host-level)

### Q: Where should I configure Tailscale access for a service?

**A**: Tailscale client configuration is Keystone. Service port exposure is documented in Relay role README. If the service needs to be accessed only via Tailscale, document this in the service README and assume Keystone's firewall policy enforces it.

### Q: What if Keystone and Relay disagree about a directory?

**A**: Keystone wins. If Keystone creates `/mnt/ssd/containers` for Podman, Relay must not modify it. Relay creates subdirectories under `/mnt/ssd/services/[service-name]`.

## Summary

**Golden Rule**: If it changes the host, it's Keystone. If it runs a service, it's Relay.

When in doubt, ask: "Could this service run on a different host provisioned the same way?" If yes → Relay. If no → probably belongs in Keystone.

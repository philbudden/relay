# Samba Role

SMB/CIFS file sharing service for NAS storage, running as a Podman container via Quadlet.

## Overview

This role deploys a containerized Samba server using the `dperson/samba` image. It exposes NAS storage via SMB/CIFS protocol for network file sharing.

## Prerequisites

**Required (provided by Keystone):**
- Podman installed and configured
- Storage mounts available at `/mnt/ssd` and `/mnt/backup`
- Quadlet directory: `/etc/containers/systemd`
- systemd as init system

**Required (manual or via Keystone):**
- Firewall rules for SMB:
  - TCP 445 (SMB)
  - TCP 139 (NetBIOS)
  - UDP 137-138 (NetBIOS name service - optional)

**Note**: Firewall configuration is **out of scope** for Relay. Configure in Keystone or manually.

## Architecture

```
┌─────────────────────────────────────────┐
│          Samba Container                │
│                                         │
│  Ports: 445 (SMB), 139 (NetBIOS)       │
│  Image: dperson/samba:latest            │
│  Network: host                          │
└─────────────────────────────────────────┘
          │                    │
          ▼                    ▼
    /mnt/ssd/shares    /mnt/backup/shares
    (read-write)       (read-only)
```

## Default Configuration

### Shares

By default, two shares are exposed:

1. **ssd** - Read-write storage on SSD
   - Path: `/mnt/ssd/shares`
   - Access: User authentication required
   - Browseable: Yes

2. **backup** - Read-only backup storage
   - Path: `/mnt/backup/shares`
   - Access: User authentication required (read-only)
   - Browseable: Yes

### Users

Default user:
- Username: `smbuser`
- Password: `changeme` ⚠️ **CHANGE THIS IN PRODUCTION**
- UID/GID: 1000

## Usage

### Basic Deployment

```yaml
# inventory/hosts.yml
all:
  hosts:
    nas:
      ansible_host: 192.168.1.100

relay_services:
  hosts:
    nas:
```

Run playbook:

```bash
ansible-playbook site.yml --tags samba
```

### Custom Configuration

Override defaults in inventory:

```yaml
# inventory/group_vars/relay_services/samba.yml
samba_workgroup: "HOMELAB"
samba_server_string: "HomeNAS"

samba_users:
  - username: "alice"
    password: "{{ vault_alice_password }}"  # Use Ansible Vault!
    uid: 1000
    gid: 1000
  - username: "bob"
    password: "{{ vault_bob_password }}"
    uid: 1001
    gid: 1001

samba_shares:
  - name: "media"
    path: "/mnt/ssd/shares/media"
    browseable: "yes"
    readonly: "no"
    guest: "no"
    users: "alice,bob"
    comment: "Media Library"
  - name: "backups"
    path: "/mnt/backup/shares"
    browseable: "yes"
    readonly: "yes"
    guest: "no"
    users: "alice,bob"
    comment: "Backup Storage"
```

### Securing Passwords with Ansible Vault

**Never commit plaintext passwords!**

```bash
# Create encrypted vars file
ansible-vault create inventory/group_vars/relay_services/vault.yml

# Add encrypted passwords
vault_alice_password: "secure_password_here"
vault_bob_password: "another_secure_password"

# Deploy with vault password
ansible-playbook site.yml --ask-vault-pass
```

## Variables

### Image Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `samba_image` | `dperson/samba` | Container image |
| `samba_image_tag` | `latest` | Image tag ⚠️ Pin for production |
| `samba_use_digest` | `false` | Use digest pinning |
| `samba_image_digest` | `""` | Image digest (if enabled) |

### Storage Paths

| Variable | Default | Description |
|----------|---------|-------------|
| `samba_base_dir` | `/mnt/ssd/services/samba` | Base directory for Samba data |
| `samba_config_dir` | `{{ samba_base_dir }}/config` | Samba configuration |
| `samba_cache_dir` | `{{ samba_base_dir }}/cache` | Samba cache |

### Network Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `samba_port_smb` | `445` | SMB port |
| `samba_port_netbios` | `139` | NetBIOS port |
| `samba_workgroup` | `WORKGROUP` | Windows workgroup |
| `samba_server_string` | `Relay NAS` | Server description |

### Share Configuration

| Variable | Type | Description |
|----------|------|-------------|
| `samba_shares` | List | Share definitions (see structure below) |

Share structure:

```yaml
- name: "share_name"          # Required: Share name
  path: "/host/path"           # Required: Host path to expose
  browseable: "yes"            # Optional: Show in browse lists
  readonly: "no"               # Optional: Read-only access
  guest: "no"                  # Optional: Allow guest access
  users: "user1,user2"         # Optional: Allowed users (comma-separated)
  comment: "Description"       # Optional: Share description
```

### User Configuration

| Variable | Type | Description |
|----------|------|-------------|
| `samba_users` | List | User definitions (see structure below) |

User structure:

```yaml
- username: "username"         # Required: Username
  password: "password"         # Required: Password (use Vault!)
  uid: 1000                    # Optional: User ID
  gid: 1000                    # Optional: Group ID
```

## Accessing Shares

### From Windows

1. Open File Explorer
2. In address bar: `\\<nas-ip>\ssd`
3. Enter credentials when prompted

### From macOS

1. Finder → Go → Connect to Server (⌘K)
2. Server Address: `smb://<nas-ip>/ssd`
3. Enter credentials when prompted

### From Linux

```bash
# Install CIFS utils
sudo apt-get install cifs-utils  # Debian/Ubuntu
sudo dnf install cifs-utils      # Fedora

# Mount share
sudo mount -t cifs //<nas-ip>/ssd /mnt/nas \
  -o username=smbuser,password=YOUR_PASSWORD,uid=1000,gid=1000
```


## Upgrading Samba

### Safe Upgrade Procedure

1. **Check release notes**
   ```bash
   # Visit: https://github.com/dperson/samba/releases
   # Review changelog for breaking changes
   ```

2. **Update image tag**
   ```yaml
   # roles/samba/defaults/main.yml or inventory override
   samba_image_tag: "NEW_TAG_OR_DIGEST"
   ```

3. **Test in check mode**
   ```bash
   ansible-playbook site.yml --tags samba --check --diff
   ```

4. **Deploy with monitoring**
   ```bash
   ansible-playbook site.yml --tags samba
   
   # Verify service started
   ssh nas systemctl status samba.service
   
   # Check logs for errors
   ssh nas journalctl -u samba.service -n 50 --no-pager
   ```

5. **Test SMB connectivity**
   ```bash
   # From client machine
   smbclient -L //nas-ip/ -U smbuser
   ```

6. **Rollback if needed**
   ```bash
   # Revert image tag in Git
   git revert HEAD
   
   # Redeploy previous version
   ansible-playbook site.yml --tags samba
   ```

### Automated Updates (Optional)

AutoUpdate is enabled by default. To use automated updates:

```bash
# Check for updates (dry run)
ssh nas podman auto-update --dry-run

# Apply updates
ssh nas podman auto-update

# Enable timer for regular checks
ssh nas systemctl enable --now podman-auto-update.timer
```

**Warning**: Automated updates can introduce breaking changes. Only enable if you monitor the NAS regularly.

## Operations

### Check Service Status

```bash
systemctl status samba.service
```

### View Logs

```bash
journalctl -u samba.service -f
```

### Restart Service

```bash
systemctl restart samba.service
```

### Check Container

```bash
podman ps | grep samba
podman logs samba
```

### Update Image

```bash
# Update image tag in defaults/main.yml or inventory
samba_image_tag: "2024.01.15"

# Re-run playbook
ansible-playbook site.yml --tags samba

# Quadlet will pull new image and recreate container
```

## Troubleshooting

### Cannot connect to shares

**Check firewall**:
```bash
# Verify ports are open
sudo ss -tlnp | grep -E '445|139'
```

If ports aren't listening, check firewall rules (Keystone responsibility).

**Check service status**:
```bash
systemctl status samba.service
journalctl -u samba.service -n 50
```

### Authentication fails

**Verify users inside container**:
```bash
podman exec -it samba pdbedit -L
```

**Check share permissions**:
```bash
ls -la /mnt/ssd/shares
```

Ensure directories exist and have correct permissions.

### "Connection refused" errors

- Verify container is running: `podman ps | grep samba`
- Check network mode: Container must use `--network=host`
- Verify firewall allows SMB traffic

### Shares not visible

- Check `browseable` setting in share definition
- Verify user has access to share (check `users` field)
- Some clients require explicit share path (e.g., `\\nas\ssd`)

## Security Considerations

### Mandatory

1. **Set passwords via Ansible Vault** - Default is empty and will fail deployment
   ```bash
   ansible-vault create inventory/group_vars/relay_services/vault.yml
   # Add: vault_samba_password: "your_secure_password"
   # Then reference: password: "{{ vault_samba_password }}"
   ```

2. **Password exposure in environment variables** - Passwords are passed to the container via environment variables. This means:
   - They are visible in `podman inspect samba`
   - They may appear in systemd journal with verbose logging
   - They are visible in the container's `/proc/<pid>/environ`
   
   This is a limitation of the `dperson/samba` container design. For typical home NAS use behind a firewall/Tailscale, this is acceptable. For higher security environments, consider alternative Samba containers that support password files or secrets management.

3. **Restrict user access** - Only grant access to specific users per share
4. **Firewall configuration** - Limit SMB access to trusted networks (Tailscale)
5. **Read-only backups** - Backup share should be read-only to prevent ransomware

### Recommended

1. **Pin image versions** - Don't use `latest` in production
2. **Regular updates** - Keep Samba image updated for security patches
3. **Audit access** - Monitor logs for unauthorized access attempts
4. **Network isolation** - Use Tailscale or VPN, never expose SMB to internet

## Migration Notes (Debian → Fedora IoT)

This role is OS-agnostic and requires no changes for Fedora IoT migration:

- ✅ Uses Podman/Quadlet (portable)
- ✅ No OS-specific packages required
- ✅ No Debian-specific paths or tools
- ✅ Container handles all Samba dependencies

Firewall configuration (out of scope) may differ between platforms.

## References

- [dperson/samba container](https://github.com/dperson/samba)
- [Podman Quadlet documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [Samba documentation](https://www.samba.org/samba/docs/)

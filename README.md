# Relay

**GitOps-driven containerized service management for NAS platform**

> 🏃 Declarative Podman container orchestration via Ansible + Quadlet

Relay manages **containerized services only** on a NAS host provisioned by [Keystone](./keystone). It follows GitOps principles: declarative, idempotent, and reproducible from Git.

## Quick Start

```bash
# 1. Install Ansible dependencies
ansible-galaxy install -r requirements.yml

# 2. Configure inventory
vim inventory/hosts.yml  # Set your NAS IP/hostname

# 3. Validate prerequisites
ansible-playbook validate.yml

# 4. Deploy services
ansible-playbook site.yml --check  # Dry run first
ansible-playbook site.yml

# 5. Verify deployment
ssh <nas-ip>
systemctl status samba.service
podman ps
```

## What is Relay?

Relay implements **Layer 2** (Services) in a two-layer architecture:

- **Layer 1 ([Keystone](./keystone))**: Host OS, storage, Podman runtime, Tailscale
- **Layer 2 (This Repository)**: Containerized services, applications, data workloads

### Separation of Concerns

| Concern | Owned By | Examples |
|---------|----------|----------|
| Host provisioning | Keystone | OS packages, RAID setup, Podman installation |
| Service deployment | Relay | Samba, media servers, databases |

This separation ensures:
- **Independent reproducibility** - Host and services can be rebuilt separately
- **Clear boundaries** - No scope creep or responsibility overlap
- **GitOps discipline** - Each layer has its own source of truth
- **Migration-ready** - Services are portable across host platforms

## Current Services

- **Samba** - SMB/CIFS file sharing for NAS storage
- **NVR** - 24/7 RTSP camera recording with daily archival

See [docs/SERVICES.md](docs/SERVICES.md) for the full service catalog.

## Architecture

### Container Orchestration Stack

```
┌────────────────────────────────────────┐
│           Git Repository               │  ← Single source of truth
└───────────────┬────────────────────────┘
                │
                ▼
┌────────────────────────────────────────┐
│          Ansible Playbook              │  ← Declarative orchestration
└───────────────┬────────────────────────┘
                │
                ▼
┌────────────────────────────────────────┐
│     Quadlet (systemd generator)        │  ← Container → systemd unit
└───────────────┬────────────────────────┘
                │
                ▼
┌────────────────────────────────────────┐
│      Podman + systemd                  │  ← Runtime + lifecycle mgmt
└────────────────────────────────────────┘
```

### Why Quadlet?

Quadlet is Podman's native systemd integration:
- **Declarative** - Container defined in `.container` files
- **systemd-native** - First-class systemd unit integration
- **Dependency-aware** - Leverages systemd dependency graph
- **Immutable** - No runtime drift, containers match definitions

Traditional `podman run` scripts are imperative and drift-prone. Quadlet ensures containers are always in declared state.

## Prerequisites

### Required (Provided by Keystone)

Relay assumes the host has been provisioned by Keystone:

✅ Podman installed and configured  
✅ Quadlet directory: `/etc/containers/systemd`  
✅ Container storage on SSD: `/mnt/ssd/podman`  
✅ Storage mounts: `/mnt/ssd` and `/mnt/backup`  
✅ systemd PID 1 with multi-user.target  
✅ Tailscale VPN (optional but recommended)

**If Keystone has not run**, Relay will fail with clear error messages.

### Manual Prerequisites

- **Firewall rules** - Configure in Keystone or manually (e.g., TCP 445/139 for Samba)
- **DNS/hostname** - Ensure NAS is reachable from control machine
- **SSH access** - Passwordless sudo recommended

## Installation

### 1. Clone Repository

```bash
git clone <your-repo-url> /opt/relay
cd /opt/relay
```

### 2. Install Dependencies

```bash
# Install Ansible collections
ansible-galaxy install -r requirements.yml

# Verify Ansible installation
ansible --version  # Requires 2.15+
```

### 3. Configure Inventory

Edit `inventory/hosts.yml`:

```yaml
relay_services:
  hosts:
    nas:
      ansible_host: 192.168.1.100  # Your NAS IP
      ansible_user: admin          # Your SSH user
```

Or use Tailscale hostname:

```yaml
ansible_host: nas.your-tailnet.ts.net
```

### 4. Validate Environment

```bash
ansible-playbook validate.yml
```

This checks:
- SSH connectivity
- Sudo access
- Keystone prerequisites (Podman, storage mounts, Quadlet directory)
- systemd status

### 5. Deploy Services

```bash
# Dry run (see what would change)
ansible-playbook site.yml --check --diff

# Apply configuration
ansible-playbook site.yml

# Deploy specific service
ansible-playbook site.yml --tags samba
```

### 6. Verify Deployment

```bash
# On NAS host
systemctl status samba.service
podman ps
journalctl -u samba.service -f
```

## Configuration

### Service-Specific Configuration

Each service has its own configuration file in `inventory/group_vars/relay_services/`:

```
inventory/group_vars/relay_services/
├── samba.yml        # Samba-specific config
├── nvr.yml          # NVR camera config
└── vault.yml        # Encrypted secrets (Ansible Vault)
```

Example `samba.yml`:

```yaml
samba_workgroup: "HOMELAB"
samba_server_string: "My NAS"

samba_users:
  - username: "alice"
    password: "{{ vault_alice_password }}"
    uid: 1000
    gid: 1000
```

### Secrets Management

**Never commit plaintext passwords!** Use Ansible Vault:

```bash
# Create encrypted vault
ansible-vault create inventory/group_vars/relay_services/vault.yml

# Add secrets
vault_alice_password: "secure_password_here"
vault_bob_password: "another_secure_password"

# Deploy with vault
ansible-playbook site.yml --ask-vault-pass
```

Store vault password securely (password manager, not in Git).

## Usage

### Common Operations

```bash
# Deploy all services
ansible-playbook site.yml

# Deploy specific service
ansible-playbook site.yml --tags samba

# Dry run (check mode)
ansible-playbook site.yml --check --diff

# Validate configuration
ansible-playbook validate.yml

# Update service image
# 1. Edit roles/[service]/defaults/main.yml
# 2. Change [service]_image_tag
# 3. Re-run playbook
ansible-playbook site.yml --tags samba
```

### Idempotency Testing

Safe to run repeatedly:

```bash
ansible-playbook site.yml  # First run: changes applied
ansible-playbook site.yml  # Second run: no changes
```

### Service Management

On NAS host:

```bash
# Status
systemctl status samba.service

# Logs
journalctl -u samba.service -f

# Restart
systemctl restart samba.service

# Container info
podman ps
podman logs samba
```

## Directory Structure

```
relay/
├── AGENTS.md                    # Architectural governance (READ FIRST)
├── README.md                    # This file
├── LICENSE                      # MIT license
├── site.yml                     # Main playbook
├── validate.yml                 # Validation playbook
├── ansible.cfg                  # Ansible configuration
├── requirements.yml             # Ansible dependencies
│
├── inventory/
│   ├── hosts.yml               # Inventory definition
│   └── group_vars/
│       └── relay_services/
│           ├── samba.yml       # Samba configuration
│           ├── nvr.yml         # NVR camera configuration
│           └── vault.yml       # Encrypted secrets (gitignored)
│
├── roles/
│   ├── samba/                  # Samba service role
│   │   ├── defaults/main.yml   # Default variables
│   │   ├── tasks/main.yml      # Deployment tasks
│   │   ├── templates/          # Quadlet templates
│   │   ├── handlers/main.yml   # systemd handlers
│   │   └── README.md           # Role documentation
│   └── nvr/                    # NVR camera recording role
│       ├── defaults/main.yml   # Default variables
│       ├── tasks/main.yml      # Deployment tasks
│       ├── templates/          # Quadlet + script templates
│       ├── handlers/main.yml   # systemd handlers
│       └── README.md           # Role documentation
│
├── docs/
│   ├── SERVICES.md             # Service catalog
│   ├── NVR-QUICKSTART.md       # NVR setup guide for new users
│   ├── QUICKREF.md             # Common commands reference
│   └── INTEGRATION.md          # Keystone/Relay boundary guide
│
└── keystone/                   # Reference to host provisioning
```

## Design Principles

### 1. GitOps-First

- Git is the **single source of truth**
- All changes are version-controlled and reviewable
- Reproducible from scratch (`git clone` → `ansible-playbook`)

### 2. Declarative & Idempotent

- State is declared in Quadlet files, not scripted
- Safe to run playbooks repeatedly
- No manual `podman run` commands

### 3. Clear Separation of Concerns

- **Relay**: Services only (containers, Quadlets, app config)
- **Keystone**: Host only (OS, storage, Podman installation)
- No boundary violations

### 4. Container-Native

- Services run in containers via Podman
- Quadlet for systemd integration
- Images pinned to specific versions (not `latest`)

### 5. Platform-Portable

- Abstracts Debian vs Fedora differences
- Designed for migration to Fedora IoT
- No OS-specific hacks

## Troubleshooting

### Playbook fails with "Keystone prerequisites not found"

**Cause**: Host not provisioned by Keystone

**Solution**: Run Keystone playbook first to provision host

```bash
cd keystone/
ansible-playbook site.yml
```

### Cannot connect to Samba shares

**Cause**: Firewall blocking SMB ports

**Solution**: Configure firewall in Keystone or manually

```bash
# Check if ports are open
sudo ss -tlnp | grep -E '445|139'

# If needed, open ports (Keystone's responsibility)
# Example for firewalld:
sudo firewall-cmd --add-port=445/tcp --permanent
sudo firewall-cmd --add-port=139/tcp --permanent
sudo firewall-cmd --reload
```

### Service fails to start

**Check logs**:

```bash
journalctl -u samba.service -n 50
```

**Check Quadlet file**:

```bash
cat /etc/containers/systemd/samba.container
systemctl cat samba.service  # View generated unit
```

**Validate manually**:

```bash
podman run --rm -it dperson/samba --help
```

### NVR cameras not recording

**Check recorder status**:

```bash
systemctl status nvr-recorder-front-door.service
journalctl -u nvr-recorder-front-door.service -n 50
```

**Verify segments are being written**:

```bash
find /mnt/ssd/services/nvr/cameras -name "*.mp4" | tail -5
```

**Check RTSP URL is reachable** (without exposing credentials):

```bash
# Test basic TCP connectivity to camera
nc -zv <camera-ip> 554
```

See [docs/NVR-QUICKSTART.md](docs/NVR-QUICKSTART.md) for a full troubleshooting guide.

### Changes not applied

**Ensure handlers run**:

```bash
# Handlers trigger on template changes
ansible-playbook site.yml --tags samba

# Force handler execution
ansible-playbook site.yml --tags samba --force-handlers
```

**Manual reload**:

```bash
sudo systemctl daemon-reload
sudo systemctl restart samba.service
```

## Documentation

- **[AGENTS.md](AGENTS.md)** - Architectural contract and governance (READ FIRST)
- **[roles/samba/README.md](roles/samba/README.md)** - Samba service documentation
- **[roles/nvr/README.md](roles/nvr/README.md)** - NVR camera recording documentation
- **[docs/SERVICES.md](docs/SERVICES.md)** - Service catalog
- **[docs/NVR-QUICKSTART.md](docs/NVR-QUICKSTART.md)** - NVR setup guide for new users
- **[docs/QUICKREF.md](docs/QUICKREF.md)** - Common commands reference
- **[Keystone README](keystone/README.md)** - Host provisioning system

## Contributing

1. **Read [AGENTS.md](AGENTS.md) first** - Understand scope and boundaries
2. **Follow conventions** - Use Quadlet, pin versions, be idempotent
3. **Test thoroughly** - Dry run, idempotency check, manual verification
4. **Document decisions** - Explain *why*, not just *what*
5. **Commit semantically** - Use [Conventional Commits](https://www.conventionalcommits.org/)

### Adding a New Service

1. Create role: `roles/[service-name]/`
2. Follow standard structure (see `roles/samba/` as example)
3. Add Quadlet template: `templates/[service].container.j2`
4. Update playbook: Add role to `site.yml`
5. Document: Create `roles/[service-name]/README.md`
6. Test: Validate idempotency and functionality

## License

See [LICENSE](LICENSE)

## Acknowledgments

- **Keystone** - Host provisioning layer
- **Podman** - Container runtime
- **Quadlet** - systemd integration for containers
- **Ansible** - Infrastructure as Code

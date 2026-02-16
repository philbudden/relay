# Relay - Container Service Management

**GitOps-driven containerized service orchestration for NAS platform**

---

## 1. Project Philosophy

Relay is responsible for **service lifecycle management only** on a NAS host provisioned by Keystone.

### Core Tenets

- **Git is the single source of truth** - All configuration is versioned and reviewable
- **Fully declarative** - State is declared, never scripted
- **Idempotent by design** - Safe to run repeatedly without side effects  
- **Reproducible from scratch** - Complete service stack can be rebuilt from Git alone
- **Minimal and boring** - No magic, no hidden automation, no clever hacks
- **Clear separation of concerns** - Relay manages services; Keystone manages host

### What This Repository Is

A **long-lived infrastructure system** that orchestrates containerized services using:
- **Ansible** - Configuration management and orchestration
- **Quadlet** - Declarative container definitions
- **systemd** - Service lifecycle and dependency management
- **Podman** - Container runtime (rootless where possible)

### What This Repository Is Not

- A host provisioning system (that's Keystone)
- A configuration management system for the OS
- A workstation bootstrap tool
- A replacement for Kubernetes
- A collection of imperative scripts

---

## 2. Scope and Non-Goals

### ✅ In Scope (This Repository)

Relay is responsible for:

- **Container definitions** - Quadlet `.container`, `.network`, `.volume` files
- **Service configuration** - Application-specific config managed declaratively
- **Image version management** - Pinned tags, optional digest pinning
- **systemd unit orchestration** - Service dependencies and restart policies
- **Volume mappings** - Binding host storage to containers
- **Network definitions** - Container networking via Quadlet
- **Update coordination** - Controlled, explicit container image updates

### ❌ Explicitly Out of Scope

Relay **must not** manage:

- Host OS configuration (packages, sysctl, kernel parameters)
- Storage provisioning (filesystems, RAID, mount units)
- Network infrastructure (firewalls, routing, Tailscale)
- Podman installation or container runtime configuration
- User account management
- Host-level security policies
- Boot or firmware configuration

**Boundary Rule**: If it requires `apt install`, modifies `/etc/sysctl.conf`, or changes firewall rules, it belongs in **Keystone**, not Relay.

### Minimal Host Interactions (Allowed)

Relay **may** perform these minimal host operations when strictly required:

1. **Create directories** for container volumes (e.g., `/mnt/ssd/services/samba/config`)
2. **Set ownership/permissions** on container-bound directories
3. **Trigger systemd daemon-reload** after deploying Quadlets
4. **Enable/start systemd units** generated from Quadlets

These must be:
- **Minimal** - Smallest possible change required
- **Explicit** - Clearly documented in role tasks
- **Justified** - Explained in role README or AGENTS.md

---

## 3. Target Architecture

### Platform Support

| Platform                  | Status      | Notes                              |
|---------------------------|-------------|------------------------------------|
| Raspberry Pi OS (Trixie)  | ✅ Primary  | Current target (Debian-based)      |
| Fedora IoT (Blueberry)    | 🎯 Planned  | Future target, design-compatible   |
| Other Debian/Fedora       | ⚠️ Untested | May work with inventory changes    |

**Migration Commitment**: All design decisions must minimize Fedora IoT migration friction.

### Host Assumptions (Guaranteed by Keystone)

Relay assumes the following host state:

1. **Podman installed and configured**
   - Quadlet directory exists: `/etc/containers/systemd`
   - Container storage on SSD: `/mnt/ssd/podman`
   - Podman socket enabled

2. **Storage primitives available**
   - SSD mounted at: `/mnt/ssd`
   - Backup RAID mounted at: `/mnt/backup`
   - Mounts are persistent (systemd mount units)

3. **systemd integration**
   - systemd is PID 1
   - `systemctl daemon-reload` available
   - Multi-user.target active

4. **Network assumptions**
   - Tailscale VPN active
   - Firewall managed by Keystone
   - Host networking available to containers

**If these assumptions are violated, Relay will fail fast and report the missing prerequisite.**

---

## 4. GitOps Workflow Model

### Repository as Single Source of Truth

```
┌─────────────────┐
│  Git Repository │  ← Single source of truth
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Ansible Playbook│  ← Declarative application
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Target Host    │  ← Converged state
│  (NAS Server)   │
└─────────────────┘
```

### Change Workflow

1. **Modify** - Edit Ansible roles, Quadlet templates, or variables in Git
2. **Review** - Pull request with diff review
3. **Merge** - Merge to main branch
4. **Pull** - Pull changes on target host (`git pull`)
5. **Apply** - Run playbook (`ansible-playbook site.yml`)
6. **Verify** - Check service status (`systemctl status`, `podman ps`)

### Idempotency Guarantee

Running the playbook multiple times must produce the same outcome:

```bash
ansible-playbook site.yml  # First run: changes applied
ansible-playbook site.yml  # Second run: no changes (idempotent)
```

---

## 5. Directory Structure Conventions

### Repository Layout

```
relay/
├── AGENTS.md                    # This file - architectural contract
├── README.md                    # User-facing documentation
├── site.yml                     # Main playbook
├── inventory/
│   ├── hosts.yml               # Inventory definition
│   └── group_vars/
│       └── relay_services/     # Service-level variables
│           └── main.yml
├── roles/
│   ├── samba/                  # Example service role
│   │   ├── defaults/
│   │   │   └── main.yml       # Default variables
│   │   ├── tasks/
│   │   │   └── main.yml       # Idempotent tasks
│   │   ├── templates/
│   │   │   └── samba.container.j2  # Quadlet template
│   │   ├── handlers/
│   │   │   └── main.yml       # systemd reload handlers
│   │   └── README.md          # Role-specific docs
│   └── [service-name]/         # Additional services...
└── docs/
    └── SERVICES.md             # Service catalog
```

### Role Structure (Standard)

Every service role must follow this structure:

```
roles/[service-name]/
├── defaults/main.yml           # REQUIRED: Default variables
├── tasks/main.yml              # REQUIRED: Idempotent tasks
├── templates/                  # REQUIRED: At least one Quadlet file
│   └── [service].container.j2
├── handlers/main.yml           # REQUIRED: systemd handlers
├── files/                      # OPTIONAL: Static config files
├── vars/                       # OPTIONAL: OS-specific overrides
│   ├── Debian.yml
│   └── Fedora.yml
└── README.md                   # RECOMMENDED: Role documentation
```

---

## 6. Quadlet Conventions

### File Naming

Quadlet files must follow systemd naming conventions:

- **Container unit**: `[service-name].container` → generates `[service-name].service`
- **Network unit**: `[network-name].network`
- **Volume unit**: `[volume-name].volume`

Example: `samba.container` → systemd generates `samba.service`

### Quadlet Template Standards

All Quadlet templates must include:

```ini
[Unit]
Description=[Service] container
After=network-online.target
Wants=network-online.target

[Container]
Image=[registry]/[image]:[tag]
ContainerName=[service-name]
AutoUpdate=registry              # Enable Podman auto-update
PublishPort=[host]:[container]   # If needed
Volume=[host-path]:[container-path]:[options]
Network=host                     # Or custom network

[Service]
Restart=always
RestartSec=10s
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
```

### Image Version Pinning

**REQUIRED**: Always pin to specific tags, never use `latest`.

```yaml
# Good
samba_image: "dperson/samba"
samba_image_tag: "2023.10.1"

# Bad
samba_image: "dperson/samba:latest"
```

**RECOMMENDED**: Pin to digest for production:

```yaml
samba_use_digest: true
samba_image_digest: "sha256:abc123..."
samba_full_image: "{{ samba_image }}@{{ samba_image_digest }}"
```

### Restart Policies

Default restart policy: `Restart=always`, `RestartSec=10s`

Override only when justified (document why in role README).

### Logging

Containers log to journald by default. No special configuration needed.

Query logs: `journalctl -u [service-name].service`

---

## 7. Ansible Role Design Principles

### Role Anatomy

Each role must:

1. **Define defaults** (`defaults/main.yml`) - Sensible, secure defaults
2. **Be idempotent** (`tasks/main.yml`) - Safe to run repeatedly
3. **Template Quadlets** (`templates/*.j2`) - Jinja2 templates for flexibility
4. **Register handlers** (`handlers/main.yml`) - systemd daemon-reload, restart

### Task Structure (Standard Pattern)

```yaml
---
# roles/[service]/tasks/main.yml

- name: Create service directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    mode: '0755'
    owner: root
    group: root
  loop:
    - "{{ service_config_dir }}"
    - "{{ service_data_dir }}"

- name: Deploy Quadlet container definition
  ansible.builtin.template:
    src: "[service].container.j2"
    dest: "/etc/containers/systemd/[service].container"
    mode: '0644'
    owner: root
    group: root
  notify:
    - reload systemd
    - restart [service]

- name: Enable and start service
  ansible.builtin.systemd:
    name: "[service].service"
    enabled: true
    state: started
    daemon_reload: true
```

### Variable Naming Convention

```yaml
# Prefix all variables with service name
[service]_image: "registry/image"
[service]_image_tag: "1.0.0"
[service]_config_dir: "/mnt/ssd/services/[service]/config"
[service]_data_dir: "/mnt/ssd/services/[service]/data"
[service]_port: 8080
```

### Handlers (Standard)

Every role must define these handlers:

```yaml
---
# roles/[service]/handlers/main.yml

- name: reload systemd
  ansible.builtin.systemd:
    daemon_reload: true

- name: restart [service]
  ansible.builtin.systemd:
    name: "[service].service"
    state: restarted
```

---

## 8. systemd Integration Model

### Service Generation

Quadlet files are placed in `/etc/containers/systemd/` and automatically converted to systemd units by `podman-systemd-generator`.

**Generator runs at**: 
- Boot time
- `systemctl daemon-reload`

**Workflow**:
1. Ansible deploys Quadlet file to `/etc/containers/systemd/[service].container`
2. Ansible triggers `systemctl daemon-reload`
3. Generator creates `/run/systemd/generator/[service].service`
4. Ansible enables and starts `[service].service`

### Service Dependencies

Use systemd `After=`, `Wants=`, `Requires=` directives in Quadlet `[Unit]` section:

```ini
[Unit]
Description=Service that depends on storage
After=mnt-ssd.mount
Requires=mnt-ssd.mount
```

### Service Ordering

**Critical**: Ensure dependencies are correct:

- `After=network-online.target` - For network-dependent services
- `After=mnt-ssd.mount` - For services requiring SSD storage
- `After=podman.socket` - For services requiring Podman API

---

## 9. Update Strategy

### Image Updates

Two update models supported:

#### 1. Manual Updates (Recommended for Stability)

```yaml
# 1. Update image tag in defaults/main.yml
samba_image_tag: "2023.11.1"  # Changed from 2023.10.1

# 2. Run playbook
ansible-playbook site.yml --tags samba

# 3. Quadlet triggers image pull and container recreation
```

#### 2. Automated Updates (Podman auto-update)

Enable in Quadlet:

```ini
[Container]
AutoUpdate=registry
Label=io.containers.autoupdate=registry
```

Then run periodically:

```bash
podman auto-update
systemctl restart podman-auto-update.service
```

**Default**: Manual updates. Enable auto-update per-service as needed.

### Configuration Changes

Changing variables in `defaults/main.yml` or inventory triggers:

1. Template regeneration (Quadlet file changes)
2. `systemctl daemon-reload` (via handler)
3. Service restart (via handler)

This is **intentional** - configuration changes require restart.

---

## 10. Testing Strategy

### Pre-Deployment (Required)

```bash
# 1. Syntax check
ansible-playbook site.yml --syntax-check

# 2. Dry run
ansible-playbook site.yml --check --diff

# 3. Specific service check
ansible-playbook site.yml --tags samba --check
```

### Idempotency Validation (Required)

```bash
# Run twice - second run should show zero changes
ansible-playbook site.yml
ansible-playbook site.yml  # Should report: "changed=0"
```

### Post-Deployment Validation

```bash
# Verify systemd units
systemctl status [service].service

# Verify containers running
podman ps

# Check logs
journalctl -u [service].service -f

# Verify networking
ss -tlnp | grep [port]
```

### Ansible Lint (Recommended)

```bash
ansible-lint site.yml
ansible-lint roles/[service]/
```

---

## 11. Migration Considerations (Debian → Fedora IoT)

### OS Abstraction

Use OS-specific variable files when necessary:

```yaml
# roles/[service]/vars/Debian.yml
package_name: samba-common-bin

# roles/[service]/vars/Fedora.yml  
package_name: samba-common-tools
```

Load conditionally:

```yaml
- name: Include OS-specific variables
  ansible.builtin.include_vars: "{{ ansible_distribution }}.yml"
  when: ansible_distribution in ['Debian', 'Fedora']
```

### Forbidden Patterns

**Never**:
- Hardcode `/etc/apt/` or `/etc/yum.repos.d/`
- Use `apt` or `dnf` modules directly (use `package` module)
- Assume Debian-specific paths (`/var/lib/dpkg`)
- Use bash-isms that require Debian GNU tools

### Preferred Patterns

**Always**:
- Use `ansible.builtin.package` module
- Use systemd paths (`/etc/systemd/system/`)
- Use Podman/Quadlet (OS-agnostic)
- Test on both Debian and Fedora (eventually)

---

## 12. Anti-Patterns to Avoid

### ❌ Forbidden

1. **Using `latest` tags**
   ```yaml
   # BAD
   image: dperson/samba:latest
   ```

2. **Imperative shell scripts**
   ```yaml
   # BAD
   - name: Start samba
     shell: |
       docker run -d --name samba ...
   ```

3. **Manual systemd units instead of Quadlets**
   ```yaml
   # BAD (for new services)
   - name: Create systemd unit
     template:
       src: samba.service.j2
   ```

4. **Non-idempotent tasks**
   ```yaml
   # BAD
   - command: podman run ...  # Runs every time!
   ```

5. **Host package installation**
   ```yaml
   # BAD - belongs in Keystone
   - package:
       name: firewalld
   ```

6. **Secrets in Git**
   ```yaml
   # BAD
   samba_password: "hunter2"  # Never!
   ```

7. **Hardcoded paths**
   ```yaml
   # BAD
   volume: /mnt/ssd/samba:/data
   
   # GOOD
   volume: "{{ samba_data_dir }}:/data"
   ```

### ✅ Preferred Patterns

1. **Pin versions explicitly**
   ```yaml
   samba_image_tag: "2023.10.1"
   ```

2. **Use Quadlet templates**
   ```jinja2
   [Container]
   Image={{ samba_full_image }}
   ```

3. **Idempotent declarative modules**
   ```yaml
   - ansible.builtin.file:
       path: "{{ samba_config_dir }}"
       state: directory
   ```

4. **Use Ansible Vault for secrets**
   ```bash
   ansible-vault encrypt_string 'password' --name 'samba_password'
   ```

5. **Parameterize everything**
   ```yaml
   samba_data_dir: "{{ relay_storage_root }}/samba/data"
   ```

---

## 13. Summary: Agent Responsibilities

When acting as an AI agent modifying this repository:

### You MUST
- Read this file first before making any changes
- Respect scope boundaries (services only, no host changes)
- Use Quadlet for new services
- Pin image versions
- Make changes idempotent
- Test with `--check` before applying
- Create semantic git commits
- Update documentation

### You MUST NOT
- Install OS packages (belongs in Keystone)
- Modify firewall rules (belongs in Keystone)
- Create storage mounts (belongs in Keystone)
- Use imperative scripts
- Hardcode secrets
- Use `latest` tags
- Blur the Keystone/Relay boundary

### When in Doubt
- Check if it modifies the host → Belongs in Keystone
- Check if it's a service → Belongs in Relay
- If uncertain → Ask the user

---

**This document is the architectural contract for Relay. Violations require explicit user approval.**

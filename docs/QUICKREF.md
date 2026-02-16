# Relay Quick Reference

Essential commands and patterns for daily operations.

## Quick Start

```bash
# 1. Install dependencies
ansible-galaxy install -r requirements.yml

# 2. Configure inventory
vim inventory/hosts.yml  # Set NAS IP

# 3. Validate
ansible-playbook validate.yml

# 4. Deploy
ansible-playbook site.yml --check  # Dry run
ansible-playbook site.yml          # Apply
```

## Common Commands

### Deployment

```bash
# Deploy all services
ansible-playbook site.yml

# Deploy specific service
ansible-playbook site.yml --tags samba

# Dry run (check mode)
ansible-playbook site.yml --check --diff

# Force handler execution
ansible-playbook site.yml --force-handlers

# Limit to specific host
ansible-playbook site.yml --limit nas
```

### Testing

```bash
# Syntax check
ansible-playbook site.yml --syntax-check

# Validation playbook
ansible-playbook validate.yml

# Lint
ansible-lint site.yml
ansible-lint roles/samba/

# Idempotency test
ansible-playbook site.yml
ansible-playbook site.yml  # Should show "changed=0"
```

### Inventory

```bash
# List hosts
ansible-inventory --list

# Show host variables
ansible-inventory --host nas

# Graph inventory
ansible-inventory --graph
```

## On NAS Host

### Service Management

```bash
# Status
systemctl status samba.service

# Logs
journalctl -u samba.service -f
journalctl -u samba.service -n 50 --no-pager

# Restart
systemctl restart samba.service

# Enable/disable
systemctl enable samba.service
systemctl disable samba.service

# Reload systemd
systemctl daemon-reload
```

### Container Management

```bash
# List containers
podman ps
podman ps -a  # Include stopped

# Logs
podman logs samba
podman logs -f samba  # Follow

# Inspect
podman inspect samba

# Execute command in container
podman exec -it samba bash

# Stats
podman stats

# Images
podman images
```

### Quadlet Management

```bash
# View Quadlet file
cat /etc/containers/systemd/samba.container

# View generated systemd unit
systemctl cat samba.service

# Regenerate units
systemctl daemon-reload

# Check generator logs
journalctl -u podman-systemd-generator
```

### Storage

```bash
# Check mounts
mount | grep -E 'mnt/(ssd|backup)'

# Disk usage
df -h /mnt/ssd /mnt/backup

# Service directories
ls -la /mnt/ssd/services/
```

### Networking

```bash
# Listening ports
ss -tlnp | grep -E '445|139'

# Firewall status
sudo firewall-cmd --list-all  # Fedora
sudo nft list ruleset          # Debian

# Test connectivity
nc -zv localhost 445
```

## Configuration Patterns

### Override Variables

```yaml
# inventory/group_vars/relay_services/samba.yml
samba_workgroup: "HOMELAB"
samba_server_string: "My NAS"
```

### Secrets with Ansible Vault

```bash
# Create vault
ansible-vault create inventory/group_vars/relay_services/vault.yml

# Edit vault
ansible-vault edit inventory/group_vars/relay_services/vault.yml

# View vault
ansible-vault view inventory/group_vars/relay_services/vault.yml

# Deploy with vault
ansible-playbook site.yml --ask-vault-pass

# Vault password file
echo "vault_password" > ~/.ansible_vault_pass
chmod 600 ~/.ansible_vault_pass
ansible-playbook site.yml --vault-password-file ~/.ansible_vault_pass
```

### Custom Shares

```yaml
# inventory/group_vars/relay_services/samba.yml
samba_shares:
  - name: "media"
    path: "/mnt/ssd/shares/media"
    browseable: "yes"
    readonly: "no"
    guest: "no"
    users: "alice,bob"
    comment: "Media Library"
```

## Troubleshooting

### Playbook Fails

```bash
# Verbose output
ansible-playbook site.yml -v    # -v, -vv, -vvv, -vvvv

# Debug specific task
ansible-playbook site.yml --start-at-task="Deploy Quadlet"

# Step through tasks
ansible-playbook site.yml --step
```

### Service Won't Start

```bash
# Check status
systemctl status samba.service

# View full logs
journalctl -u samba.service -b

# Check Quadlet syntax
cat /etc/containers/systemd/samba.container

# Test image pull manually
podman pull dperson/samba:latest

# Check dependencies
systemctl list-dependencies samba.service
```

### Container Issues

```bash
# Check if container exists
podman ps -a | grep samba

# Remove and recreate
podman stop samba
podman rm samba
systemctl daemon-reload
systemctl start samba.service

# Check image
podman images | grep samba

# Manual test run
podman run --rm -it dperson/samba --help
```

### Network Issues

```bash
# Check if service is listening
ss -tlnp | grep 445

# Test locally
nc -zv localhost 445

# Check firewall
sudo firewall-cmd --list-ports  # Fedora
sudo nft list ruleset | grep 445  # Debian

# Check container networking
podman inspect samba | grep -i network
```

## File Locations

### Relay Repository
- `/opt/relay` - Repository root
- `/opt/relay/inventory/hosts.yml` - Inventory
- `/opt/relay/roles/` - Service roles
- `/opt/relay/site.yml` - Main playbook

### On NAS Host
- `/etc/containers/systemd/` - Quadlet definitions
- `/mnt/ssd/services/[service]/` - Service data
- `/mnt/ssd/shares/` - Samba shares (SSD)
- `/mnt/backup/shares/` - Samba shares (backup)

### systemd Units
- `/etc/systemd/system/` - User-defined units
- `/run/systemd/generator/` - Generated units (Quadlet)

### Logs
- `journalctl -u samba.service` - Service logs
- `/var/log/syslog` or `/var/log/messages` - System logs

## Git Workflow

```bash
# Check status
git status

# Review changes
git diff

# Stage changes
git add -A

# Commit with semantic message
git commit -m "feat(service): Add new service"

# View history
git log --oneline

# DO NOT push (per user instruction)
# git push
```

## Update Patterns

### Update Service Configuration

```bash
# 1. Edit variables
vim inventory/group_vars/relay_services/samba.yml

# 2. Commit changes
git add inventory/group_vars/relay_services/samba.yml
git commit -m "config(samba): Update workgroup name"

# 3. Apply changes
ansible-playbook site.yml --tags samba
```

### Update Container Image

```bash
# 1. Edit role defaults
vim roles/samba/defaults/main.yml
# Change: samba_image_tag: "2024.01.15"

# 2. Commit changes
git add roles/samba/defaults/main.yml
git commit -m "chore(samba): Update to version 2024.01.15"

# 3. Deploy
ansible-playbook site.yml --tags samba
# Quadlet will pull new image and recreate container
```

## Emergency Procedures

### Rollback Service

```bash
# 1. Stop service
systemctl stop samba.service

# 2. Revert Git commit
git revert HEAD
# or
git reset --hard HEAD~1  # CAUTION: Loses uncommitted changes

# 3. Redeploy
ansible-playbook site.yml --tags samba
```

### Remove Service

```bash
# 1. Stop and disable
systemctl stop samba.service
systemctl disable samba.service

# 2. Remove Quadlet
rm /etc/containers/systemd/samba.container

# 3. Reload systemd
systemctl daemon-reload

# 4. Remove container
podman stop samba
podman rm samba

# 5. Optional: Remove data
rm -rf /mnt/ssd/services/samba
```

### Complete Reset

```bash
# CAUTION: This removes ALL services

# Stop all relay services
systemctl stop samba.service

# Remove Quadlets
rm /etc/containers/systemd/*.container

# Reload systemd
systemctl daemon-reload

# Remove all containers
podman stop -a
podman rm -a

# Optional: Remove data
rm -rf /mnt/ssd/services/*

# Redeploy from Git
cd /opt/relay
git pull
ansible-playbook site.yml
```

## Performance

### Check Resource Usage

```bash
# Container stats
podman stats

# systemd resource usage
systemd-cgtop

# Disk I/O
iotop

# Network usage
iftop
```

### Container Auto-Update

```bash
# Check auto-update status
podman auto-update --dry-run

# Run auto-update
podman auto-update

# Enable timer (if desired)
systemctl enable --now podman-auto-update.timer
systemctl status podman-auto-update.timer
```

## Documentation Quick Links

- [AGENTS.md](../AGENTS.md) - Architectural contract
- [README.md](../README.md) - Main documentation
- [SERVICES.md](SERVICES.md) - Service catalog
- [INTEGRATION.md](INTEGRATION.md) - Keystone/Relay boundary
- [roles/samba/README.md](../roles/samba/README.md) - Samba docs

## Getting Help

1. Check service logs: `journalctl -u [service].service`
2. Review AGENTS.md for architectural boundaries
3. Check INTEGRATION.md for prerequisite issues
4. Review role README for service-specific details
5. Validate configuration: `ansible-playbook validate.yml`

# NVR Role

Declarative 24/7 RTSP camera recording with daily archival, running as Podman containers via Quadlet.

## Overview

This role deploys a containerised NVR (Network Video Recorder) system using the `linuxserver/ffmpeg` image. It:

- Records each camera 24/7 into 5-minute MP4 segments
- Concatenates the previous day's segments into a single 24-hour file at 01:00 UTC
- Deletes source segments after successful concatenation
- Retains a rolling window of daily recordings (default: 30 days)
- Handles RTSP credentials securely via Ansible Vault + EnvironmentFile

No motion detection, no web UI, no database. Intentionally boring infrastructure.

## Prerequisites

**Required (provided by Keystone):**
- Podman installed and configured
- Storage mount at `/mnt/ssd`
- Quadlet directory: `/etc/containers/systemd`
- systemd as init system

**Note**: Firewall configuration is out of scope for Relay. RTSP is outbound-only (pull recording); no inbound ports are required.

## Architecture

```
┌──────────────────────────┐   ┌──────────────────────────┐
│  nvr-recorder-[cam1]     │   │  nvr-recorder-[cam2]     │
│  (Quadlet, continuous)   │   │  (Quadlet, continuous)   │
│  FFmpeg RTSP → segments  │   │  FFmpeg RTSP → segments  │
└────────────┬─────────────┘   └────────────┬─────────────┘
             │                              │
             ▼                              ▼
/mnt/ssd/services/nvr/cameras/
  [cam1]/segments/YYYY-MM-DD/HH-MM-SS.mp4
  [cam2]/segments/YYYY-MM-DD/HH-MM-SS.mp4
             │
      01:00 UTC (systemd timer)
             │
             ▼
┌──────────────────────────┐
│  nvr-concat              │
│  (Quadlet, oneshot)      │
│  Concat → daily MP4      │
│  Delete segments         │
│  Prune > 30 days         │
└──────────────────────────┘
  [cam1]/daily/YYYY-MM-DD.mp4
  [cam2]/daily/YYYY-MM-DD.mp4
```

## Quick Start

### 1. Create vault file

```bash
ansible-vault create inventory/group_vars/relay_services/vault.yml
```

Add RTSP URLs (one per camera):

```yaml
vault_nvr_front_door_rtsp_url: "rtsp://admin:password@192.168.1.50:554/stream1"
vault_nvr_back_yard_rtsp_url: "rtsp://admin:password@192.168.1.51:554/stream1"
```

### 2. Configure cameras

Create `inventory/group_vars/relay_services/nvr.yml`:

```yaml
nvr_cameras:
  - name: front-door
    rtsp_url: "{{ vault_nvr_front_door_rtsp_url }}"
  - name: back-yard
    rtsp_url: "{{ vault_nvr_back_yard_rtsp_url }}"

# Optional overrides
nvr_retention_days: 30
nvr_segment_duration: 300  # 5 minutes
```

### 3. Deploy

```bash
ansible-playbook site.yml --tags nvr --ask-vault-pass
```

## Variables

### Image Configuration

| Variable | Default | Description |
|---|---|---|
| `nvr_image` | `lscr.io/linuxserver/ffmpeg` | Container image |
| `nvr_image_tag` | `7.0.2-ls25` | Pinned image tag |
| `nvr_use_digest` | `false` | Enable digest pinning |
| `nvr_image_digest` | `""` | Image digest (if enabled) |

### Storage Paths

| Variable | Default | Description |
|---|---|---|
| `nvr_base_dir` | `{{ relay_storage_root }}/nvr` | NVR base directory |
| `nvr_cameras_dir` | `{{ nvr_base_dir }}/cameras` | Per-camera recordings |
| `nvr_scripts_dir` | `{{ nvr_base_dir }}/scripts` | Deployed scripts |
| `nvr_secrets_dir` | `/etc/containers/secrets` | RTSP credential files |

### Recording Settings

| Variable | Default | Description |
|---|---|---|
| `nvr_segment_duration` | `300` | Seconds per segment (5 min) |
| `nvr_retention_days` | `30` | Rolling daily retention window |
| `nvr_rtsp_transport` | `tcp` | RTSP transport (`tcp` or `udp`) |
| `nvr_ffmpeg_loglevel` | `warning` | FFmpeg log verbosity |

### Scheduling

| Variable | Default | Description |
|---|---|---|
| `nvr_concat_timer_oncalendar` | `*-*-* 01:00:00 UTC` | Concat timer schedule |
| `nvr_restart_sec` | `30s` | Restart delay on failure |

### Camera List

| Variable | Type | Description |
|---|---|---|
| `nvr_cameras` | List | Camera definitions (required) |

Camera structure:

```yaml
- name: "camera-name"     # Required: unique identifier, used in service and path names
  rtsp_url: "rtsp://..."  # Required: full RTSP URL with credentials (use Vault!)
```

## Storage Layout

```
/mnt/ssd/services/nvr/
├── scripts/
│   ├── nvr-record.sh      # Recorder wrapper (deployed by Ansible)
│   └── nvr-concat.sh      # Concat + prune script (deployed by Ansible)
└── cameras/
    └── [camera-name]/
        ├── segments/
        │   └── YYYY-MM-DD/
        │       └── HH-MM-SS.mp4  (5-minute clips)
        └── daily/
            └── YYYY-MM-DD.mp4    (24-hour concatenated recording)

/etc/containers/secrets/
└── nvr-cam-[name].env    # NVR_RTSP_URL=... (mode 0600, root-only)
```

## Operations

### Check recorder status

```bash
systemctl status nvr-recorder-front-door.service
journalctl -u nvr-recorder-front-door.service -f
```

### Check concat timer

```bash
systemctl list-timers nvr-concat.timer
journalctl -u nvr-concat.service
```

### Trigger concat manually (e.g. to recover missed run)

```bash
systemctl start nvr-concat.service
journalctl -u nvr-concat.service -f
```

### List running recorder containers

```bash
podman ps --filter name=nvr-recorder
```

### Check today's segment count per camera

```bash
find /mnt/ssd/services/nvr/cameras -name "*.mp4" -path "*/segments/*" | \
  awk -F/ '{print $(NF-2)}' | sort | uniq -c
```

### Add a new camera

1. Add Vault-encrypted RTSP URL to vault file
2. Add entry to `nvr_cameras` in inventory
3. Run: `ansible-playbook site.yml --tags nvr --ask-vault-pass`

## Midnight Behaviour

At midnight UTC, FFmpeg attempts to write to `segments/YYYY-MM-DD+1/HH-MM-SS.mp4`.
Since the new date directory does not exist, FFmpeg exits. systemd restarts the
container after `RestartSec` (default 30s). The wrapper script creates the new
date directory and recording resumes.

**Maximum gap at midnight: ~30 seconds.** Acceptable for surveillance use cases.
Reduce `nvr_restart_sec` to `5s` if tighter continuity is required.

## Upgrading FFmpeg Image

```bash
# 1. Check new tag at https://github.com/linuxserver/docker-ffmpeg/releases
# 2. Update in inventory or defaults/main.yml
nvr_image_tag: "7.1.0-ls26"

# 3. Test in check mode
ansible-playbook site.yml --tags nvr --check --diff --ask-vault-pass

# 4. Deploy
ansible-playbook site.yml --tags nvr --ask-vault-pass
```

## Security Notes

- RTSP credentials are stored **only** in:
  - Ansible Vault (encrypted in Git)
  - `/etc/containers/secrets/nvr-cam-[name].env` (mode `0600`, root-only)
- Credentials are **never** visible in Quadlet files, systemd unit files, or `podman inspect`
- `no_log: true` on all Ansible tasks that handle RTSP URLs
- Camera network traffic is inbound-only RTSP pull — no ports are published

## Migration Notes (Debian → Fedora IoT)

- ✅ No OS packages installed — container-only
- ✅ No Debian-specific paths or tools
- ✅ Volume mounts use `:Z` SELinux relabelling (Fedora-compatible)
- ✅ Shell scripts use POSIX `sh` (no bash-isms)
- ✅ `ansible.builtin.systemd` is OS-agnostic
- ✅ Quadlet path `/etc/containers/systemd` is identical on both platforms

## References

- [linuxserver/ffmpeg image](https://github.com/linuxserver/docker-ffmpeg)
- [FFmpeg segment muxer](https://ffmpeg.org/ffmpeg-formats.html#segment_002c-stream_005fsegment_002c-ssegment)
- [Podman Quadlet documentation](https://docs.podman.io/en/latest/markdown/podman-systemd.unit.5.html)
- [systemd.timer](https://www.freedesktop.org/software/systemd/man/systemd.timer.html)

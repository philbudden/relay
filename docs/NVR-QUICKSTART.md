# NVR Quickstart Guide

This guide walks you through setting up 24/7 camera recording on your NAS from scratch. No prior knowledge of Relay or FFmpeg is required.

**What you'll end up with:**
- Each camera recording continuously, saved as 5-minute clips
- One daily recording file per camera, assembled automatically at 01:00 UTC
- Old recordings automatically deleted after 30 days (configurable)
- Camera passwords stored securely — never visible in configuration files or logs

**Time to complete:** ~20 minutes

---

## Before You Start

You'll need:

1. **A NAS with Relay deployed** — see the main [README](../README.md) to set that up first
2. **An IP camera that supports RTSP** — most network cameras do (Hikvision, Dahua, Reolink, Amcrest, etc.)
3. **The camera's RTSP URL** — see [Finding Your RTSP URL](#1-find-your-rtsp-url) below
4. **A control machine** (your laptop/desktop) with Ansible installed and the Relay repo cloned

> **What is RTSP?**  
> RTSP (Real-Time Streaming Protocol) is the standard way IP cameras expose their video stream over the network. Think of it like a URL for a live video feed — `rtsp://user:pass@192.168.1.50:554/stream1`. Relay uses FFmpeg to pull this stream and save it to disk.

---

## Step 1: Find Your RTSP URL

Every camera manufacturer uses a slightly different RTSP URL format. Here are the most common:

| Brand | Example URL |
|-------|-------------|
| Hikvision | `rtsp://admin:password@192.168.1.50:554/Streaming/Channels/101` |
| Dahua | `rtsp://admin:password@192.168.1.50:554/cam/realmonitor?channel=1&subtype=0` |
| Reolink | `rtsp://admin:password@192.168.1.50:554/h264Preview_01_main` |
| Amcrest | `rtsp://admin:password@192.168.1.50:554/cam/realmonitor?channel=1&subtype=0` |
| Generic ONVIF | `rtsp://admin:password@192.168.1.50:554/onvif1` |

**Where to find yours:**
- Check your camera's web interface under *Network → Video → RTSP* (or similar)
- Search online for `[your camera model] RTSP URL`
- Try an ONVIF tool like [ONVIF Device Manager](https://sourceforge.net/projects/onvifdm/) (Windows)

**Test the URL before continuing** — from any machine on your network with VLC installed:

```
VLC → Media → Open Network Stream → paste your RTSP URL
```

Or from the command line:

```bash
ffplay -rtsp_transport tcp "rtsp://admin:password@192.168.1.50:554/stream1"
```

If you see a live video feed, the URL is correct. Fix it now before going further — it's much easier to debug at this stage.

---

## Step 2: Secure Your Camera Credentials

Camera RTSP URLs contain your username and password. Relay stores these using **Ansible Vault** — an encryption tool built into Ansible. Your credentials are encrypted before they ever touch disk or Git.

### Create or open your vault file

If you don't have one yet:

```bash
ansible-vault create inventory/group_vars/relay_services/vault.yml
```

You'll be prompted to set a vault password. Choose something strong and store it in your password manager — you'll need it every time you deploy.

If a vault file already exists (e.g. you have Samba passwords in it):

```bash
ansible-vault edit inventory/group_vars/relay_services/vault.yml
```

### Add one entry per camera

Inside the vault file, add your RTSP URLs like this:

```yaml
# One line per camera — use the exact URL you tested in Step 1
vault_nvr_front_door_rtsp_url: "rtsp://admin:password@192.168.1.50:554/stream1"
vault_nvr_back_yard_rtsp_url: "rtsp://admin:password@192.168.1.51:554/stream1"
```

**Naming convention:** `vault_nvr_[camera-name]_rtsp_url`  
Camera names must be lowercase letters, digits, and hyphens only (e.g. `front-door`, `back-yard`, `garage`).

Save and close. The file is now encrypted — you can safely commit it to Git.

---

## Step 3: Configure Your Cameras

Create a plain-text (unencrypted) configuration file for the NVR:

```bash
# Create the file
cat > inventory/group_vars/relay_services/nvr.yml << 'EOF'
---
nvr_cameras:
  - name: front-door
    rtsp_url: "{{ vault_nvr_front_door_rtsp_url }}"
  - name: back-yard
    rtsp_url: "{{ vault_nvr_back_yard_rtsp_url }}"
EOF
```

Each `name` must exactly match the name you used in the vault file (without the `vault_nvr_` prefix and `_rtsp_url` suffix).

### Optional: Customise settings

Add any of these to `nvr.yml` to override the defaults:

```yaml
# How many days of daily recordings to keep (default: 30)
nvr_retention_days: 30

# How long each segment clip is in seconds (default: 300 = 5 minutes)
nvr_segment_duration: 300

# When to run the daily concatenation job (systemd OnCalendar format, UTC)
nvr_concat_timer_oncalendar: "*-*-* 01:00:00 UTC"

# Set to "info" if you need more verbose logs for debugging
nvr_ffmpeg_loglevel: "warning"
```

---

## Step 4: Deploy

### Dry run first (recommended)

Preview what Ansible will do without making any changes:

```bash
ansible-playbook site.yml --tags nvr --check --diff --ask-vault-pass
```

Check the output looks reasonable — you should see directories being created, Quadlet files being deployed, and services being started.

### Apply

```bash
ansible-playbook site.yml --tags nvr --ask-vault-pass
```

Ansible will:
1. Create recording directories on the NAS
2. Deploy the recorder and concat scripts
3. Write encrypted credentials to `/etc/containers/secrets/` (mode 0600) on the NAS
4. Deploy a systemd container unit per camera
5. Deploy the daily concatenation job and its timer
6. Start everything

---

## Step 5: Verify It's Working

SSH into your NAS and run these checks:

### Are the recorders running?

```bash
# Replace front-door with your camera name
systemctl status nvr-recorder-front-door.service
```

You should see `active (running)`. The logs will show FFmpeg output — something like:

```
Input: rtsp://... [connected]
Output: /recordings/segments/2026-03-01/14-30-00.mp4
```

### Are segment files being created?

```bash
find /mnt/ssd/services/nvr/cameras -name "*.mp4" -newer /tmp -ls
```

Within 5 minutes of starting, you should see `.mp4` files appearing in `segments/YYYY-MM-DD/`.

### Is the concat timer scheduled?

```bash
systemctl list-timers nvr-concat.timer
```

You'll see the next scheduled run time (01:00 UTC).

### Check all NVR containers at once

```bash
podman ps --filter name=nvr
```

---

## How It Works Day-to-Day

### Recording (continuous)

Each camera runs as its own container (`nvr-recorder-[name]`). FFmpeg connects to the camera's RTSP stream and saves it in 5-minute chunks:

```
/mnt/ssd/services/nvr/cameras/
  front-door/
    segments/
      2026-03-01/
        14-30-00.mp4    ← 5-minute clip
        14-35-00.mp4
        14-40-00.mp4
        ...
```

If the connection drops, the container restarts automatically within 30 seconds.

### Daily archival (01:00 UTC)

Every morning at 01:00 UTC, a job runs that:
1. Takes all of yesterday's 5-minute segments for each camera
2. Joins them into a single 24-hour file (stream-copy, no re-encoding — fast and lossless)
3. Deletes the segments **only if the join succeeded**
4. Removes daily files older than your retention limit

```
/mnt/ssd/services/nvr/cameras/
  front-door/
    daily/
      2026-02-28.mp4    ← full 24-hour recording
      2026-03-01.mp4
```

### At midnight

There is a ~30-second gap in recording at midnight UTC while the container restarts to create the new date directory. This is by design and acceptable for home NVR use.

---

## Adding a Camera Later

1. Add its vault entry:
   ```bash
   ansible-vault edit inventory/group_vars/relay_services/vault.yml
   # Add: vault_nvr_garage_rtsp_url: "rtsp://..."
   ```

2. Add it to `nvr.yml`:
   ```yaml
   nvr_cameras:
     - name: front-door
       rtsp_url: "{{ vault_nvr_front_door_rtsp_url }}"
     - name: garage                               # new
       rtsp_url: "{{ vault_nvr_garage_rtsp_url }}" # new
   ```

3. Deploy:
   ```bash
   ansible-playbook site.yml --tags nvr --ask-vault-pass
   ```

Existing cameras are unaffected — Ansible is idempotent.

---

## Viewing Your Recordings

Recordings are plain MP4 files. Play them with any video player.

**Via Samba** (if deployed): browse to `\\<nas-ip>\ssd` → `services/nvr/cameras/`

**Via SSH:**

```bash
ls /mnt/ssd/services/nvr/cameras/front-door/daily/
ls /mnt/ssd/services/nvr/cameras/front-door/segments/
```

**Check disk usage:**

```bash
du -sh /mnt/ssd/services/nvr/cameras/*/
```

---

## Triggering the Concat Job Manually

If you want to run the daily job now (e.g. to recover a missed night):

```bash
systemctl start nvr-concat.service
journalctl -u nvr-concat.service -f   # watch progress
```

> The job processes **yesterday's** date. If you need to recover an older date, contact the relay maintainer — manual FFmpeg concat is straightforward.

---

## Troubleshooting

### Recorder service fails to start

```bash
# Check the status and last 30 log lines
systemctl status nvr-recorder-front-door.service
journalctl -u nvr-recorder-front-door.service -n 30 --no-pager
```

**Common causes:**

| Symptom in logs | Likely cause | Fix |
|---|---|---|
| `Connection refused` or `Connection timed out` | Camera IP is wrong or camera is off | Check IP, ping camera |
| `401 Unauthorized` | Wrong username or password | Re-check RTSP URL in vault |
| `No such file or directory: /usr/local/bin/nvr-record.sh` | Scripts not deployed | Re-run playbook |
| `Cannot open display` or similar | Wrong Entrypoint in container | Re-run playbook (image may have changed) |
| Container keeps restarting | RTSP stream interrupted | Normal — check camera is online |

### Test the RTSP URL without deploying

SSH to the NAS and run:

```bash
# Replace <rtsp-url> with your actual URL
podman run --rm lscr.io/linuxserver/ffmpeg:7.0.2-ls25 \
  -rtsp_transport tcp -i "<rtsp-url>" \
  -t 10 -c copy /tmp/test.mp4 && echo "SUCCESS"
```

If this produces a 10-second clip, recording will work. If it errors, the problem is with the URL or camera — not Relay.

### Concat job fails

```bash
journalctl -u nvr-concat.service --no-pager
```

If concat fails, **segments are preserved** — no footage is lost. Fix the underlying issue then re-run `systemctl start nvr-concat.service`.

### No recordings after a gap (power cut, network outage)

The recorders restart automatically when the NAS comes back up (systemd `Restart=always`). The concat job has `Persistent=true` on its timer, so a missed 01:00 UTC run fires as soon as the NAS is back online.

### "Camera name is invalid" error during deployment

Camera names must be lowercase letters, digits, and hyphens only:

```yaml
# Bad
- name: "Front Door"      # spaces not allowed
- name: "camera_1"        # underscores not allowed
- name: "CAM1"            # uppercase not allowed

# Good
- name: "front-door"
- name: "camera-1"
- name: "cam1"
```

### Disk filling up

Check how much space recordings are using:

```bash
du -sh /mnt/ssd/services/nvr/cameras/*/
df -h /mnt/ssd
```

Options:
- Reduce `nvr_retention_days` in `nvr.yml` and redeploy
- Reduce `nvr_segment_duration` (smaller segments; same total data)
- Add more storage (Keystone's responsibility)

A rough guide: 1080p H.264 at typical camera bitrates uses **2–6 GB per camera per day**.

---

## Updating the FFmpeg Image

Check the [linuxserver/ffmpeg releases page](https://github.com/linuxserver/docker-ffmpeg/releases) for new versions.

```bash
# Edit the image tag
vim roles/nvr/defaults/main.yml
# Change: nvr_image_tag: "7.1.0-ls26"

# Commit
git add roles/nvr/defaults/main.yml
git commit -m "chore(nvr): Update FFmpeg to 7.1.0-ls26"

# Deploy
ansible-playbook site.yml --tags nvr --ask-vault-pass
```

---

## Reference

| Path | Contents |
|------|----------|
| `/mnt/ssd/services/nvr/cameras/[name]/segments/YYYY-MM-DD/` | 5-minute clip files (deleted after concat) |
| `/mnt/ssd/services/nvr/cameras/[name]/daily/` | 24-hour archive files |
| `/mnt/ssd/services/nvr/scripts/` | Recording and concat scripts |
| `/etc/containers/secrets/nvr-cam-[name].env` | Encrypted RTSP URL (0600, root only) |
| `/etc/containers/systemd/nvr-recorder-[name].container` | Quadlet: per-camera recorder |
| `/etc/containers/systemd/nvr-concat.container` | Quadlet: daily concat job |
| `/etc/systemd/system/nvr-concat.timer` | Timer: fires at 01:00 UTC |

| Command | Purpose |
|---------|---------|
| `systemctl status nvr-recorder-[name].service` | Check recorder is running |
| `journalctl -u nvr-recorder-[name].service -f` | Live recorder logs |
| `systemctl list-timers nvr-concat.timer` | When concat next runs |
| `systemctl start nvr-concat.service` | Run concat job now |
| `journalctl -u nvr-concat.service` | Concat job logs |
| `podman ps --filter name=nvr` | All NVR containers |

---

## Next Steps

- **[roles/nvr/README.md](../roles/nvr/README.md)** — Full variable reference and architecture details
- **[docs/SERVICES.md](SERVICES.md)** — Complete service catalog
- **[docs/QUICKREF.md](QUICKREF.md)** — Common Relay commands

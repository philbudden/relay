# PLAN.md
## Add Datetime Overlay + Staggered Daily Concatenation

### Status
Ready for implementation

---

## 1. Design Constraints (DO NOT CHANGE)

- No overlay during live recording
- No JavaScript / Node / Python runtime
- FFmpeg only
- One FFmpeg concat job at a time
- Segment recording remains `-c copy`
- Overlay applied only during daily concat
- Compatible with ARM64 (CM5)

---

## 2. Configuration Additions

### New defaults (`roles/recorder/defaults/main.yml`)

```yaml
recorder_overlay_timestamp: true
recorder_timestamp_format: "%Y-%m-%d %H:%M:%S"
recorder_timestamp_font: "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
recorder_timestamp_fontsize: 24
recorder_timestamp_x: 10
recorder_timestamp_y: 10

# Staggering
recorder_concat_start_hour_utc: 1
recorder_concat_spacing_minutes: 30
```

---

## 3. Required Image Change (FFmpeg fonts)

### Preferred: Custom FFmpeg image

`roles/recorder/files/Dockerfile.ffmpeg`

```Dockerfile
FROM docker.io/jrottenberg/ffmpeg:6.1-alpine
RUN apk add --no-cache font-dejavu
```

---

## 4. Datetime Overlay Implementation

Overlay is applied **only during daily concatenation**.

### drawtext filter template

```text
drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf:
text='%{localtime\:%Y-%m-%d %H\\:%M\\:%S}':
x=10:y=10:
fontsize=24:
fontcolor=white:
box=1:
boxcolor=black@0.5
```

---

## 5. Concat Behaviour

- Operates on previous UTC day
- Generates ordered concat list
- Re-encodes with overlay
- Deletes segments only on success

---

## 6. FFmpeg Concat Command

```bash
ffmpeg   -f concat   -safe 0   -i concat.txt   -vf "<DRAW_TEXT_FILTER>"   -c:v libx264   -preset veryfast   -crf 23   -c:a copy   /recordings/daily/YYYY-MM-DD.mp4
```

---

## 7. Staggered Scheduling

Each camera has its own timer offset by index.

Example (30 min spacing):
- cam0: 01:00 UTC
- cam1: 01:30 UTC
- cam2: 02:00 UTC

---

## 8. systemd Timer Template

```ini
[Timer]
OnCalendar=*-*-* 01:00:00
Persistent=true
```

---

## 9. concat.sh Script (inside container)

```sh
#!/bin/sh
set -eu

YESTERDAY=$(date -u -d "yesterday" +%F)
SEG_DIR="/recordings/segments/$YESTERDAY"
OUT_FILE="/recordings/daily/$YESTERDAY.mp4"

[ -d "$SEG_DIR" ] || exit 0

ls "$SEG_DIR"/*.mp4 | sort | sed "s/^/file '/;s/$/'/" > /tmp/concat.txt

ffmpeg   -f concat   -safe 0   -i /tmp/concat.txt   -vf "$DRAW_TEXT_FILTER"   -c:v libx264   -preset veryfast   -crf 23   -c:a copy   "$OUT_FILE"

[ -s "$OUT_FILE" ] && rm -rf "$SEG_DIR"
```

---

## 10. Acceptance Criteria

- Timestamp visible and accurate
- Correct when scrubbing
- No parallel concat jobs
- No credential exposure
- Declarative via Ansible


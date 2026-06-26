#!/bin/sh

set -eu

REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${REPO_ROOT}/roles/nvr/templates/nvr-record.sh.j2"
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "${TEST_ROOT}"
}

trap cleanup EXIT HUP INT TERM

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains_line() {
  file="$1"
  expected="$2"
  grep -qx -- "${expected}" "${file}" || fail "expected ${file} to contain '${expected}'"
}

make_fake_ffmpeg() {
  fake_bin="$1"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/ffmpeg" <<'EOF'
#!/bin/sh
set -eu

printf '%s\n' "$@" > "${FFMPEG_ARGS_FILE}"
output=""
for arg in "$@"; do
  output="${arg}"
done

mkdir -p "$(dirname "${output}")"
: > "${output}"
EOF
  chmod +x "${fake_bin}/ffmpeg"
}

test_recorder_uses_audio_resample_and_aac() {
  fake_bin="${TEST_ROOT}/bin"
  recordings_dir="${TEST_ROOT}/recordings"
  args_file="${TEST_ROOT}/ffmpeg-args"

  make_fake_ffmpeg "${fake_bin}"

  env \
    PATH="${fake_bin}:${PATH}" \
    FFMPEG_ARGS_FILE="${args_file}" \
    NVR_RECORDINGS_DIR="${recordings_dir}" \
    NVR_RTSP_URL="rtsp://example.local/stream" \
    NVR_SEGMENT_DURATION=300 \
    NVR_RTSP_TRANSPORT=tcp \
    NVR_FFMPEG_LOGLEVEL=warning \
    NVR_RW_TIMEOUT=30000000 \
    sh "${SCRIPT}"

  [ -d "${recordings_dir}/segments/$(date -u +%Y-%m-%d)" ] || fail "expected today's segment directory"

  assert_contains_line "${args_file}" "-map"
  assert_contains_line "${args_file}" "0:v:0"
  assert_contains_line "${args_file}" "0:a:0?"
  assert_contains_line "${args_file}" "-c:v"
  assert_contains_line "${args_file}" "copy"
  assert_contains_line "${args_file}" "-c:a"
  assert_contains_line "${args_file}" "aac"
  assert_contains_line "${args_file}" "-af"
  assert_contains_line "${args_file}" "aresample=async=1:first_pts=0"
}

test_recorder_uses_audio_resample_and_aac

echo "PASS: nvr record harness"

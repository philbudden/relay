#!/bin/sh

set -eu

REPO_ROOT="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"
SCRIPT="${REPO_ROOT}/roles/nvr/templates/nvr-concat.sh.j2"
REAL_DATE="$(command -v date)"
TEST_ROOT="$(mktemp -d /tmp/nvr-concat-test-XXXXXX)"

cleanup() {
  rm -rf "${TEST_ROOT}"
}

trap cleanup EXIT HUP INT TERM

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "expected file to exist: $1"
}

assert_no_file() {
  [ ! -e "$1" ] || fail "expected path to be absent: $1"
}

assert_dir() {
  [ -d "$1" ] || fail "expected directory to exist: $1"
}

assert_no_dir() {
  [ ! -d "$1" ] || fail "expected directory to be absent: $1"
}

assert_eq() {
  actual="$1"
  expected="$2"
  message="$3"
  [ "${actual}" = "${expected}" ] || fail "${message} (expected '${expected}', got '${actual}')"
}

make_fake_tools() {
  fake_bin="$1"
  mkdir -p "${fake_bin}"

  cat > "${fake_bin}/date" <<EOF
#!/bin/sh
if [ "\$#" -eq 4 ] && [ "\$1" = "-u" ] && [ "\$2" = "-d" ] && [ "\$3" = "yesterday" ] && [ "\$4" = "+%Y-%m-%d" ]; then
  printf '%s\n' "\${FAKE_YESTERDAY}"
  exit 0
fi
exec "${REAL_DATE}" "\$@"
EOF
  chmod +x "${fake_bin}/date"

  cat > "${fake_bin}/ffmpeg" <<'EOF'
#!/bin/sh
set -eu

call_count_file="${FFMPEG_LOG_DIR}/call-count"
call_count=0

if [ -f "${call_count_file}" ]; then
  call_count="$(cat "${call_count_file}")"
fi

call_count=$((call_count + 1))
printf '%s\n' "${call_count}" > "${call_count_file}"

call_dir="${FFMPEG_LOG_DIR}/call-${call_count}"
mkdir -p "${call_dir}"
printf '%s\n' "$@" > "${call_dir}/args"

input=""
output=""
prev=""

for arg in "$@"; do
  if [ "${prev}" = "-i" ]; then
    input="${arg}"
  fi
  prev="${arg}"
  output="${arg}"
done

[ -n "${input}" ] || exit 2
cp "${input}" "${call_dir}/list"
printf '%s\n' "${output}" > "${call_dir}/output"
printf '%s\n' "${output%.tmp.*}" > "${call_dir}/final-output"

if [ -n "${FFMPEG_FAIL_MATCH:-}" ] && printf '%s\n' "${output}" | grep -q "${FFMPEG_FAIL_MATCH}" && [ ! -f "${FFMPEG_LOG_DIR}/failed-once" ]; then
  : > "${FFMPEG_LOG_DIR}/failed-once"
  exit 1
fi

printf 'synthetic-output\n' > "${output}"
EOF
  chmod +x "${fake_bin}/ffmpeg"
}

make_segments() {
  segments_dir="$1"
  mkdir -p "${segments_dir}"

  for hour in \
    00 01 02 03 04 05 06 07 08 09 10 11 \
    12 13 14 15 16 17 18 19 20 21 22 23; do
    for minute in 00 05 10 15 20 25 30 35 40 45 50 55; do
      : > "${segments_dir}/${hour}-${minute}-00.mp4"
    done
  done
}

run_concat() {
  fake_bin="$1"
  cameras_dir="$2"
  log_dir="$3"
  shift 3

  mkdir -p "${log_dir}"

  env \
    PATH="${fake_bin}:${PATH}" \
    FAKE_YESTERDAY=2026-03-01 \
    FFMPEG_LOG_DIR="${log_dir}" \
    NVR_CAMERAS_DIR="${cameras_dir}" \
    RETENTION_DAYS=7 \
    "$@" \
    sh "${SCRIPT}"
}

assert_window_count() {
  log_dir="$1"
  call_number="$2"
  expected_output="$3"

  actual_output="$(basename "$(cat "${log_dir}/call-${call_number}/final-output")")"
  assert_eq "${actual_output}" "${expected_output}" "unexpected output filename for ffmpeg call ${call_number}"

  count="$(wc -l < "${log_dir}/call-${call_number}/list" | tr -d ' ')"
  assert_eq "${count}" "72" "unexpected segment count for ${expected_output}"
}

test_stream_copy_grouping_and_retention() {
  test_dir="${TEST_ROOT}/stream-copy"
  fake_bin="${test_dir}/bin"
  log_dir="${test_dir}/logs"
  camera_dir="${test_dir}/cameras/front-door"
  segments_dir="${camera_dir}/segments/2026-03-01"
  daily_dir="${camera_dir}/daily"

  mkdir -p "${daily_dir}"
  make_fake_tools "${fake_bin}"
  make_segments "${segments_dir}"

  for window in 00-06 06-12 12-18 18-24; do
    : > "${daily_dir}/2026-02-20_${window}.mp4"
  done
  : > "${daily_dir}/2026-02-20.mp4"
  : > "${daily_dir}/2026-02-23_00-06.mp4"

  run_concat "${fake_bin}" "${test_dir}/cameras" "${log_dir}"

  for window in 00-06 06-12 12-18 18-24; do
    assert_file "${daily_dir}/2026-03-01_${window}.mp4"
  done
  assert_no_dir "${segments_dir}"

  assert_eq "$(cat "${log_dir}/call-count")" "4" "stream-copy run should invoke ffmpeg four times"
  assert_window_count "${log_dir}" 1 "2026-03-01_00-06.mp4"
  assert_window_count "${log_dir}" 2 "2026-03-01_06-12.mp4"
  assert_window_count "${log_dir}" 3 "2026-03-01_12-18.mp4"
  assert_window_count "${log_dir}" 4 "2026-03-01_18-24.mp4"

  all_segments="${test_dir}/all-segments"
  cat "${log_dir}"/call-*/list | sed "s/^file '//; s/'$//" > "${all_segments}"
  total_segments="$(wc -l < "${all_segments}" | tr -d ' ')"
  unique_segments="$(sort "${all_segments}" | uniq | wc -l | tr -d ' ')"
  assert_eq "${total_segments}" "288" "expected every segment to appear exactly once across all windows"
  assert_eq "${unique_segments}" "288" "expected no duplicate segments across windows"

  for window in 00-06 06-12 12-18 18-24; do
    assert_no_file "${daily_dir}/2026-02-20_${window}.mp4"
  done
  assert_no_file "${daily_dir}/2026-02-20.mp4"
  assert_file "${daily_dir}/2026-02-23_00-06.mp4"
}

test_overlay_uses_window_basetimes() {
  test_dir="${TEST_ROOT}/overlay"
  fake_bin="${test_dir}/bin"
  log_dir="${test_dir}/logs"
  camera_dir="${test_dir}/cameras/front-door"
  segments_dir="${camera_dir}/segments/2026-03-01"
  font_file="${test_dir}/DejaVuSans.ttf"

  make_fake_tools "${fake_bin}"
  make_segments "${segments_dir}"
  : > "${font_file}"

  run_concat \
    "${fake_bin}" \
    "${test_dir}/cameras" \
    "${log_dir}" \
    NVR_TIMESTAMP_OVERLAY=1 \
    NVR_TIMESTAMP_FONT="${font_file}" \
    NVR_TIMESTAMP_FONTSIZE=28

  assert_eq "$(cat "${log_dir}/call-count")" "4" "overlay run should invoke ffmpeg four times"

  epoch_00="$("${REAL_DATE}" -u -d "2026-03-01 00:00:00" +%s)"
  epoch_06="$("${REAL_DATE}" -u -d "2026-03-01 06:00:00" +%s)"
  epoch_12="$("${REAL_DATE}" -u -d "2026-03-01 12:00:00" +%s)"
  epoch_18="$("${REAL_DATE}" -u -d "2026-03-01 18:00:00" +%s)"

  grep -q -- "-vf" "${log_dir}/call-1/args" || fail "expected overlay ffmpeg call to include -vf"
  grep -q "${epoch_00}" "${log_dir}/call-1/args" || fail "expected 00-06 overlay basetime"
  grep -q "${epoch_06}" "${log_dir}/call-2/args" || fail "expected 06-12 overlay basetime"
  grep -q "${epoch_12}" "${log_dir}/call-3/args" || fail "expected 12-18 overlay basetime"
  grep -q "${epoch_18}" "${log_dir}/call-4/args" || fail "expected 18-24 overlay basetime"
}

test_missing_window_fails_without_deletion() {
  test_dir="${TEST_ROOT}/missing-window"
  fake_bin="${test_dir}/bin"
  log_dir="${test_dir}/logs"
  camera_dir="${test_dir}/cameras/front-door"
  segments_dir="${camera_dir}/segments/2026-03-01"
  daily_dir="${camera_dir}/daily"

  mkdir -p "${daily_dir}"
  make_fake_tools "${fake_bin}"
  make_segments "${segments_dir}"
  rm -f "${segments_dir}"/12-*-00.mp4 "${segments_dir}"/13-*-00.mp4 "${segments_dir}"/14-*-00.mp4 \
    "${segments_dir}"/15-*-00.mp4 "${segments_dir}"/16-*-00.mp4 "${segments_dir}"/17-*-00.mp4

  if run_concat "${fake_bin}" "${test_dir}/cameras" "${log_dir}"; then
    fail "expected concat to fail when a required 6-hour window is empty"
  fi

  assert_dir "${segments_dir}"
  assert_eq "$(cat "${log_dir}/call-count" 2>/dev/null || printf '0')" "0" "empty window should fail before ffmpeg runs"

  for window in 00-06 06-12 12-18 18-24; do
    assert_no_file "${daily_dir}/2026-03-01_${window}.mp4"
  done
}

test_partial_failure_is_rerunnable() {
  test_dir="${TEST_ROOT}/rerun"
  fake_bin="${test_dir}/bin"
  fail_log_dir="${test_dir}/logs-fail"
  rerun_log_dir="${test_dir}/logs-rerun"
  camera_dir="${test_dir}/cameras/front-door"
  segments_dir="${camera_dir}/segments/2026-03-01"
  daily_dir="${camera_dir}/daily"

  mkdir -p "${daily_dir}"
  make_fake_tools "${fake_bin}"
  make_segments "${segments_dir}"

  if run_concat "${fake_bin}" "${test_dir}/cameras" "${fail_log_dir}" FFMPEG_FAIL_MATCH="_12-18.mp4"; then
    fail "expected synthetic ffmpeg failure"
  fi

  assert_dir "${segments_dir}"
  assert_eq "$(cat "${fail_log_dir}/call-count")" "3" "failure run should stop after the failed window"
  assert_file "${daily_dir}/2026-03-01_00-06.mp4"
  assert_file "${daily_dir}/2026-03-01_06-12.mp4"
  assert_no_file "${daily_dir}/2026-03-01_12-18.mp4"
  assert_no_file "${daily_dir}/2026-03-01_18-24.mp4"

  run_concat "${fake_bin}" "${test_dir}/cameras" "${rerun_log_dir}"

  assert_eq "$(cat "${rerun_log_dir}/call-count")" "2" "rerun should only build missing windows"
  assert_no_dir "${segments_dir}"
  assert_file "${daily_dir}/2026-03-01_12-18.mp4"
  assert_file "${daily_dir}/2026-03-01_18-24.mp4"
}

test_stream_copy_grouping_and_retention
test_overlay_uses_window_basetimes
test_missing_window_fails_without_deletion
test_partial_failure_is_rerunnable

echo "PASS: nvr concat harness"

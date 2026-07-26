#!/usr/bin/env bash
set -uo pipefail

# Live progress is observability only. Nothing in this script is allowed to
# stop the actual ROM build, even when contract/telemetry state is missing.
stage_key="${1:-}"
stage_state="${2:-}"
completed_stages="${3:-0}"
message="${4:-}"

if [[ -z "$stage_key" || -z "$stage_state" ]]; then
  printf '%s\n' '[DeadZone System] live stage arguments missing; skipping update.' >&2
  exit 0
fi

case "$completed_stages" in
  ''|*[!0-9]*) completed_stages=0 ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || true)"
if [[ -z "$script_dir" ]]; then
  printf '%s\n' '[DeadZone System] live script directory unavailable; skipping update.' >&2
  exit 0
fi

repo_root="$(cd "$script_dir/.." 2>/dev/null && pwd || true)"
stage_started_at="${DZ_STAGE_STARTED_AT:-${BUILD_STARTED_AT:-}}"
request_id="${REQUEST_ID:-}"
sound_pid_file="${RUNNER_TEMP:-/tmp}/deadzone-lite-sound-${request_id:-build}.pid"

stop_sound_reminder() {
  [[ -f "$sound_pid_file" ]] || return 0
  local pid
  pid="$(cat "$sound_pid_file" 2>/dev/null || true)"
  if [[ "$pid" =~ ^[0-9]+$ ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -f "$sound_pid_file" 2>/dev/null || true
}

start_sound_reminder() {
  [[ "${DEADZONE_CONTROLLED_BUILD:-0}" == "1" ]] || return 0
  [[ -f "$script_dir/build_sound_reminder.sh" ]] || return 0
  [[ -x "$script_dir/build_sound_reminder.sh" ]] \
    || chmod +x "$script_dir/build_sound_reminder.sh" 2>/dev/null \
    || return 0
  [[ -f "$sound_pid_file" ]] && return 0

  nohup bash "$script_dir/build_sound_reminder.sh" >/dev/null 2>&1 &
  printf '%s\n' "$!" > "$sound_pid_file" 2>/dev/null || true
}

if [[ "$stage_state" == "in_progress" ]]; then
  stage_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    {
      printf 'DZ_CURRENT_STAGE_KEY=%s\n' "$stage_key"
      printf 'DZ_COMPLETED_STAGES=%s\n' "$completed_stages"
      printf 'DZ_STAGE_STARTED_AT=%s\n' "$stage_started_at"
    } >> "$GITHUB_ENV" 2>/dev/null \
      || printf '%s\n' '[DeadZone System] live environment update deferred; build continues.' >&2
  fi
fi

case "$stage_key:$stage_state" in
  building:in_progress) start_sound_reminder || true ;;
  finalizing:in_progress|finalizing:success|*:failed|*:cancelled) stop_sound_reminder || true ;;
esac

# Bot telemetry requires the signed request id. A missing id must never convert
# an observability update into a failed GitHub Actions step.
if [[ -n "$request_id" && -f "$script_dir/send_telemetry.py" ]]; then
  if ! python3 "$script_dir/send_telemetry.py" \
    --request-id "$request_id" \
    --stage-key "$stage_key" \
    --stage-state "$stage_state" \
    --completed-stages "$completed_stages" \
    --total-stages 8 \
    --build-started-at "${BUILD_STARTED_AT:-}" \
    --stage-started-at "$stage_started_at" \
    --message "$message"; then
    printf '%s\n' '[DeadZone System] live telemetry deferred; build continues.' >&2
  fi
else
  printf '%s\n' '[DeadZone System] live telemetry skipped: request state unavailable.' >&2
fi

# build.sh owns Start -> Download -> Extract -> Build so the visible progress
# never jumps backwards. The launcher only bridges the later stages to the
# same Lite message after build.sh returns.
if [[ "${DEADZONE_CONTROLLED_BUILD:-0}" == "1" \
   && -n "$repo_root" \
   && -f "$repo_root/engine/notify.py" ]]; then
  notify_stage=""
  case "$stage_key:$stage_state" in
    packaging:in_progress) notify_stage="pack" ;;
    preparing_upload:in_progress) notify_stage="pack" ;;
    uploading:in_progress) notify_stage="upload" ;;
    finalizing:success) notify_stage="success" ;;
    *:failed) notify_stage="fail" ;;
    *:cancelled) notify_stage="cancelled" ;;
  esac

  if [[ -n "$notify_stage" ]]; then
    (
      cd "$repo_root/engine" 2>/dev/null || exit 0
      timeout "${DEADZONE_NOTIFY_TIMEOUT_SECONDS:-8}s" \
        python3 notify.py \
          "$notify_stage" "DeadZone_Lite" "${INPUT_URL:-}" "mezo-lite" \
          "${BUILDER_NAME:-}" "${BUILDER_ID:-}" \
        || printf '%s\n' '[DeadZone System] Lite Telegram render deferred; build continues.' >&2
    ) || true
  fi
fi

exit 0

#!/usr/bin/env bash
set -uo pipefail

stage_key="${1:?stage key is required}"
stage_state="${2:?stage state is required}"
completed_stages="${3:?completed stage count is required}"
message="${4:-}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
stage_started_at="${DZ_STAGE_STARTED_AT:-${BUILD_STARTED_AT:-}}"

if [[ "$stage_state" == "in_progress" ]]; then
  stage_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -n "${GITHUB_ENV:-}" ]]; then
    {
      printf 'DZ_CURRENT_STAGE_KEY=%s\n' "$stage_key"
      printf 'DZ_COMPLETED_STAGES=%s\n' "$completed_stages"
      printf 'DZ_STAGE_STARTED_AT=%s\n' "$stage_started_at"
    } >> "$GITHUB_ENV" || printf '%s\n' '[DeadZone System] live environment update deferred; build continues.' >&2
  fi
fi

if ! python3 "$script_dir/send_telemetry.py" \
  --request-id "${REQUEST_ID:?request ID is required}" \
  --stage-key "$stage_key" \
  --stage-state "$stage_state" \
  --completed-stages "$completed_stages" \
  --total-stages 8 \
  --build-started-at "${BUILD_STARTED_AT:-}" \
  --stage-started-at "$stage_started_at" \
  --message "$message"; then
  printf '%s\n' '[DeadZone System] live update deferred; build continues.' >&2
fi

# build.sh owns Start -> Download -> Extract -> Build so the visible progress
# never jumps backwards. The launcher only bridges the later stages to the
# same Lite message after build.sh returns.
if [[ "${DEADZONE_CONTROLLED_BUILD:-0}" == "1" && -f "$repo_root/engine/notify.py" ]]; then
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
      cd "$repo_root/engine" || exit 0
      timeout "${DEADZONE_NOTIFY_TIMEOUT_SECONDS:-8}s" \
        python3 notify.py \
          "$notify_stage" "DeadZone_Lite" "${INPUT_URL:-}" "mezo-lite" \
          "${BUILDER_NAME:-}" "${BUILDER_ID:-}" \
        || printf '%s\n' '[DeadZone System] Lite Telegram render deferred; build continues.' >&2
    )
  fi
fi

# Live telemetry/rendering is observability only. It must never stop the build.
exit 0

#!/usr/bin/env bash
set -uo pipefail

stage_key="${1:?stage key is required}"
stage_state="${2:?stage state is required}"
completed_stages="${3:?completed stage count is required}"
message="${4:-}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Live telemetry is observability only. It must never create a second build
# message or stop the actual engine when Telegram/control delivery is delayed.
exit 0

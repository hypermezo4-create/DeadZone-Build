#!/usr/bin/env bash
set -uo pipefail

# Non-blocking Telegram audio reminders for DeadZone Lite builds.
# `once` sends the proof-of-life cue synchronously; `loop` waits 15 minutes
# between later reminders. Audio failure is presentation-only and never fails ROM build.

mode="${1:-loop}"
interval="${DEADZONE_BUILD_SOUND_INTERVAL_SECONDS:-900}"
case "$interval" in
  ''|*[!0-9]*) interval=900 ;;
esac
(( interval >= 60 )) || interval=60

log() {
  printf '[DeadZone Sound] %s\n' "$*" >&2
}

[[ "${DEADZONE_CONTROLLED_BUILD:-0}" == "1" ]] || { log "skipped: uncontrolled build"; exit 0; }
[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] || { log "skipped: TELEGRAM_BOT_TOKEN missing"; exit 0; }
[[ -n "${TELEGRAM_MSG_CHAT_ID:-}" ]] || { log "skipped: TELEGRAM_MSG_CHAT_ID missing"; exit 0; }
command -v ffmpeg >/dev/null 2>&1 || { log "skipped: ffmpeg missing"; exit 0; }
command -v curl >/dev/null 2>&1 || { log "skipped: curl missing"; exit 0; }

work="${RUNNER_TEMP:-/tmp}/deadzone-build-sounds-${REQUEST_ID:-lite}"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

make_audio() {
  local output="$1" filter="$2"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "$filter" -t 1.45 -c:a libmp3lame -b:a 96k "$output" >/dev/null 2>&1
}

# Short premium-style notification cues. No speech, so Arabic/English builds
# share the same sound without mixing interface languages.
make_audio "$work/01.mp3" "sine=frequency=659:sample_rate=48000,volume=0.10,afade=t=out:st=0.9:d=0.45" || true
make_audio "$work/02.mp3" "sine=frequency=523:sample_rate=48000,volume=0.09,tremolo=f=6:d=0.30,afade=t=out:st=0.9:d=0.45" || true
make_audio "$work/03.mp3" "sine=frequency=784:sample_rate=48000,volume=0.08,vibrato=f=5:d=0.16,afade=t=out:st=0.9:d=0.45" || true

tracks=("$work/01.mp3" "$work/02.mp3" "$work/03.mp3")

send_audio() {
  local index="${1:-0}"
  local audio="${tracks[$((index % ${#tracks[@]}))]}"
  [[ -s "$audio" ]] || { log "skipped: generated audio is empty"; return 0; }

  local response_file="$work/telegram-response.json"
  local http_code
  http_code="$(curl --silent --show-error \
    --connect-timeout 5 --max-time 20 \
    --output "$response_file" --write-out '%{http_code}' \
    -F "chat_id=${TELEGRAM_MSG_CHAT_ID}" \
    -F "audio=@${audio};type=audio/mpeg" \
    -F "title=DeadZone Lite" \
    -F "performer=DeadZone System" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendAudio" 2>/dev/null || true)"

  if [[ "$http_code" == "200" ]] && grep -q '"ok"[[:space:]]*:[[:space:]]*true' "$response_file" 2>/dev/null; then
    log "sent"
    return 0
  fi

  local description
  description="$(python3 - "$response_file" <<'PY' 2>/dev/null || true
import json, sys
try:
    data = json.load(open(sys.argv[1], encoding='utf-8'))
    print(str(data.get('description') or 'Telegram rejected audio')[:180])
except Exception:
    print('Telegram audio request failed')
PY
)"
  log "deferred: ${description:-Telegram audio request failed}"
  return 0
}

case "$mode" in
  once)
    send_audio 0
    ;;
  loop)
    index=1
    while sleep "$interval"; do
      send_audio "$index"
      index=$((index + 1))
    done
    ;;
  *)
    log "unknown mode: $mode"
    ;;
esac

exit 0

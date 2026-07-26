#!/usr/bin/env bash
set -uo pipefail

# Non-blocking Telegram voice reminders for long DeadZone Lite builds.
# The first cue is immediate so even short/failed builds prove the sound path is
# alive; subsequent cues repeat at the configured interval. This must never
# affect the ROM build.

interval="${DEADZONE_BUILD_SOUND_INTERVAL_SECONDS:-900}"
case "$interval" in
  ''|*[!0-9]*) interval=900 ;;
esac
(( interval >= 60 )) || interval=60

[[ "${DEADZONE_CONTROLLED_BUILD:-0}" == "1" ]] || exit 0
[[ -n "${TELEGRAM_BOT_TOKEN:-}" ]] || exit 0
[[ -n "${TELEGRAM_MSG_CHAT_ID:-}" ]] || exit 0
command -v ffmpeg >/dev/null 2>&1 || exit 0
command -v curl >/dev/null 2>&1 || exit 0

work="${RUNNER_TEMP:-/tmp}/deadzone-build-sounds-${REQUEST_ID:-lite}"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT

make_voice() {
  local output="$1" filter="$2"
  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "$filter" -t 1.35 -c:a libopus -b:a 48k "$output" >/dev/null 2>&1
}

# Three short notification patterns. No speech, so Arabic/English builds use the
# same cue without mixing languages into the live experience.
make_voice "$work/01.ogg" "sine=frequency=660:sample_rate=48000,volume=0.11,afade=t=out:st=0.9:d=0.4" || true
make_voice "$work/02.ogg" "sine=frequency=520:sample_rate=48000,volume=0.09,tremolo=f=6:d=0.35,afade=t=out:st=0.9:d=0.4" || true
make_voice "$work/03.ogg" "sine=frequency=784:sample_rate=48000,volume=0.08,vibrato=f=5:d=0.18,afade=t=out:st=0.9:d=0.4" || true

voices=("$work/01.ogg" "$work/02.ogg" "$work/03.ogg")
index=0

send_voice() {
  local voice="${voices[$((index % ${#voices[@]}))]}"
  index=$((index + 1))
  [[ -s "$voice" ]] || return 0
  curl --silent --show-error --fail-with-body \
    --connect-timeout 5 --max-time 20 \
    -F "chat_id=${TELEGRAM_MSG_CHAT_ID}" \
    -F "voice=@${voice};type=audio/ogg" \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendVoice" \
    >/dev/null 2>&1 || true
}

# Immediate proof-of-life cue at the real build stage.
send_voice

while sleep "$interval"; do
  send_voice
done

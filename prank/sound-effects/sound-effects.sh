#!/bin/sh
# prank-name: Sound effects
# prank-summary: A random sound plays at random moments during working hours
#
#   sh prank/sound-effects/sound-effects.sh             install today's random schedule (cron)
#   sh prank/sound-effects/sound-effects.sh play        play one random sound right now
#   sh prank/sound-effects/sound-effects.sh status      show what is currently scheduled
#   sh prank/sound-effects/sound-effects.sh installed   exit 0 if scheduled, 1 if not
#   sh prank/sound-effects/sound-effects.sh uninstall   remove everything from crontab
#
# Configuration (environment variables, all optional):
#   PRANK_SOUNDS_DIR   folder with sound files          (default: sounds/ next to this script)
#   PRANK_COUNT        sounds per day                   (default: 4)
#   PRANK_START        start of the window, HH:MM        (default: 09:15)
#   PRANK_END          end of the window, HH:MM          (default: 17:15)
#   PRANK_DAYS         cron day-of-week spec             (default: 1-5, Mon-Fri)
#   PRANK_VOLUME       playback gain, 1 is normal        (default: 1)
#   PRANK_SYSTEM_VOLUME  built-in speakers volume while playing, %  (default: 80)

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_PATH="$SCRIPT_DIR/$(basename "$0")"

SOUNDS_DIR=${PRANK_SOUNDS_DIR:-"$SCRIPT_DIR/sounds"}
COUNT=${PRANK_COUNT:-4}
START=${PRANK_START:-09:15}
END=${PRANK_END:-17:15}
DAYS=${PRANK_DAYS:-1-5}
VOLUME=${PRANK_VOLUME:-1}
SYSTEM_VOLUME=${PRANK_SYSTEM_VOLUME:-80}

LOG_FILE="$HOME/Library/Logs/cookie-prank.log"
SPEAKER_PLAY_SOURCE="$SCRIPT_DIR/speaker-play.swift"
SPEAKER_PLAY="$HOME/Library/Application Support/cookie-prank/speaker-play"
BEGIN_MARK="# >>> cookie-prank sound-effects >>>"
END_MARK="# <<< cookie-prank sound-effects <<<"

die() {
	printf 'sound-effects: %s\n' "$1" >&2
	exit 1
}

# A random non-negative integer, from /dev/urandom so it works under plain sh.
random_int() {
	od -An -N4 -tu4 /dev/urandom | tr -d ' \n'
}

# random_below MAX -> integer in [0, MAX)
random_below() {
	max=$1
	[ "$max" -gt 0 ] || die "internal: random_below needs a positive bound"
	printf '%s\n' "$(($(random_int) % max))"
}

# "HH:MM" -> minutes since midnight
to_minutes() {
	case $1 in
	[0-9][0-9]:[0-9][0-9]) ;;
	*) die "expected a HH:MM time, got '$1'" ;;
	esac
	hours=${1%:*}
	minutes=${1#*:}
	# ${x#0} strips the leading zero so 09 is not read as octal.
	printf '%s\n' "$((${hours#0} * 60 + ${minutes#0}))"
}

list_sounds() {
	find "$SOUNDS_DIR" -maxdepth 1 -type f \
		\( -name '*.mp3' -o -name '*.m4a' -o -name '*.wav' -o -name '*.aiff' -o -name '*.aif' \) |
		sort
}

# Everything in the current crontab that is not ours.
foreign_crontab() {
	crontab -l 2>/dev/null |
		awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
			$0 == begin { ours = 1; next }
			$0 == end   { ours = 0; next }
			!ours       { print }
		'
}

write_crontab() {
	# Buffering stdin keeps `crontab -l` from being read while `crontab -`
	# is already replacing the file.
	new_crontab=$(cat)
	printf '%s\n' "$new_crontab" | crontab -
}

# Compiles the built-in speakers player when it is missing or stale. Fails
# quietly without the developer tools: calling the swiftc stub would pop up an
# install dialog on their screen and give the game away.
build_speaker_play() {
	[ -x "$SPEAKER_PLAY" ] && [ ! "$SPEAKER_PLAY_SOURCE" -nt "$SPEAKER_PLAY" ] && return 0
	xcode-select -p >/dev/null 2>&1 || return 1
	mkdir -p "$(dirname "$SPEAKER_PLAY")"
	swiftc -O -o "$SPEAKER_PLAY.tmp" "$SPEAKER_PLAY_SOURCE" >/dev/null 2>&1 &&
		mv "$SPEAKER_PLAY.tmp" "$SPEAKER_PLAY"
}

# Plays on the default output, unmuted but at its own volume: it may be
# headphones, where forcing the volume up is not safe.
play_on_default_output() {
	was_muted=$(osascript -e 'output muted of (get volume settings)') || was_muted=""
	osascript -e 'set volume without output muted' || true
	status=0
	afplay -v "$VOLUME" "$1" || status=$?
	[ "$was_muted" = true ] && osascript -e 'set volume with output muted'
	return "$status"
}

cmd_play() {
	case $SYSTEM_VOLUME in
	'' | *[!0-9]*) die "PRANK_SYSTEM_VOLUME must be a whole number from 0 to 100" ;;
	esac
	[ "$SYSTEM_VOLUME" -le 100 ] || die "PRANK_SYSTEM_VOLUME must be a whole number from 0 to 100"
	sounds=$(list_sounds)
	[ -n "$sounds" ] || die "no sound files in $SOUNDS_DIR — drop some .mp3 files in there"

	total=$(printf '%s\n' "$sounds" | wc -l | tr -d ' ')
	pick=$(($(random_below "$total") + 1))
	sound=$(printf '%s\n' "$sounds" | sed -n "${pick}p")

	printf '%s playing %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$sound"
	# The speakers player only fails before making a sound (no built-in speakers,
	# unreadable file), so falling back never plays the sound twice.
	if build_speaker_play && "$SPEAKER_PLAY" "$sound" "$SYSTEM_VOLUME" "$VOLUME"; then
		return 0
	fi
	play_on_default_output "$sound"
}

cmd_install() {
	sounds=$(list_sounds)
	[ -n "$sounds" ] || die "no sound files in $SOUNDS_DIR — drop some .mp3 files in there"
	[ "$COUNT" -ge 1 ] || die "PRANK_COUNT must be at least 1"

	window_start=$(to_minutes "$START")
	window_end=$(to_minutes "$END")
	window=$((window_end - window_start))
	[ "$window" -ge "$COUNT" ] || die "the window $START-$END is too short for $COUNT sounds"

	mkdir -p "$(dirname "$LOG_FILE")"
	speakers_note="on the built-in speakers"
	build_speaker_play || speakers_note="(on the built-in speakers only; no developer tools to build the speakers player, so sounds play on the selected output at its own volume)"

	# Split the window into equal blocks and pick a random minute inside each,
	# so the times are unpredictable but never bunched up.
	block=$((window / COUNT))
	schedule=""
	slot=0
	while [ "$slot" -lt "$COUNT" ]; do
		at=$((window_start + slot * block + $(random_below "$block")))
		schedule="$schedule$((at % 60)) $((at / 60))
"
		slot=$((slot + 1))
	done

	{
		foreign_crontab
		printf '%s\n' "$BEGIN_MARK"
		# Re-roll tomorrow's times before the window opens, so no two days match.
		# The settings ride along, so a customised schedule stays customised.
		printf '%s %s * * %s %s /bin/sh %s reschedule\n' \
			0 "$((window_start / 60))" "$DAYS" "$(config_env)" \
			"$(shell_quote "$SCRIPT_PATH")"
		settings=$(config_env)
		printf '%s\n' "$schedule" | while read -r minute hour; do
			[ -n "${hour:-}" ] || continue
			printf '%s %s * * %s %s /bin/sh %s play >> %s 2>&1\n' \
				"$minute" "$hour" "$DAYS" "$settings" \
				"$(shell_quote "$SCRIPT_PATH")" "$(shell_quote "$LOG_FILE")"
		done
		printf '%s\n' "$END_MARK"
	} | write_crontab

	printf 'Scheduled %s sound(s) on days %s, between %s and %s:\n' \
		"$COUNT" "$DAYS" "$START" "$END"
	printf '%s\n' "$schedule" | while read -r minute hour; do
		[ -n "${hour:-}" ] || continue
		printf '  %02d:%02d\n' "$hour" "$minute"
	done
	printf 'Sounds come from %s (%s file(s)), at %s%% volume %s.\n' \
		"$SOUNDS_DIR" "$(list_sounds | wc -l | tr -d ' ')" "$SYSTEM_VOLUME" "$speakers_note"
	printf 'Times are re-rolled every morning at %02d:00.\n' "$((window_start / 60))"
	printf 'Undo with: sh %s uninstall\n' "$0"
}

# Wrap a path in single quotes so spaces survive the trip through cron's shell.
shell_quote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# The active settings as assignments, to prefix the reschedule command with.
config_env() {
	printf 'PRANK_SOUNDS_DIR=%s PRANK_COUNT=%s PRANK_START=%s PRANK_END=%s PRANK_DAYS=%s PRANK_VOLUME=%s PRANK_SYSTEM_VOLUME=%s' \
		"$(shell_quote "$SOUNDS_DIR")" "$(shell_quote "$COUNT")" \
		"$(shell_quote "$START")" "$(shell_quote "$END")" \
		"$(shell_quote "$DAYS")" "$(shell_quote "$VOLUME")" \
		"$(shell_quote "$SYSTEM_VOLUME")"
}

cmd_uninstall() {
	foreign_crontab | write_crontab
	rm -f "$SPEAKER_PLAY" "$SPEAKER_PLAY.tmp"
	printf 'Removed the sound-effects schedule from your crontab.\n'
}

our_crontab() {
	crontab -l 2>/dev/null |
		awk -v begin="$BEGIN_MARK" -v end="$END_MARK" '
			$0 == begin { ours = 1; next }
			$0 == end   { ours = 0; next }
			ours        { print }
		'
}

cmd_installed() {
	[ -n "$(our_crontab)" ]
}

cmd_status() {
	entries=$(our_crontab)
	if [ -z "$entries" ]; then
		printf 'Nothing scheduled.\n'
		return 0
	fi
	printf 'Scheduled:\n%s\n' "$entries"
	[ -f "$LOG_FILE" ] && printf '\nRecent plays (%s):\n%s\n' \
		"$LOG_FILE" "$(tail -n 5 "$LOG_FILE")"
	return 0
}

case "${1:-install}" in
install) cmd_install ;;
reschedule) cmd_install >/dev/null 2>&1 ;;
play) cmd_play ;;
status) cmd_status ;;
installed) cmd_installed ;;
uninstall) cmd_uninstall ;;
*) die "unknown command '$1' — use install, play, status, installed or uninstall" ;;
esac

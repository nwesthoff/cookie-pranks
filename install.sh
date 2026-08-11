#!/bin/sh
# Pick which pranks are installed.
#
#   sh install.sh                     choose interactively
#   sh install.sh sound-effects ...   install these by name, no prompting
#   sh install.sh --list              print the available pranks and exit
#
# The menu opens with the installed pranks already ticked, so it shows the
# desired end state: tick to install, untick to remove, enter to apply.
#
# Interactive keys: up/down or j/k to move, space to tick, enter to apply,
# a to tick all, r to reset to what is installed, q to quit.
#
# Every prank is a folder in prank/ holding <name>.sh next to the assets that
# script needs. It advertises itself with two header comments, and is installed
# by running it with no arguments:
#
#   # prank-name: Sound effects
#   # prank-summary: A random sound plays at random moments during working hours

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PRANK_DIR="$SCRIPT_DIR/prank"

ESC=$(printf '\033')
CR=$(printf '\r')
NL=$(printf '\nX')
NL=${NL%X}

# Styling, but only when we are actually drawing to a terminal.
if [ -t 1 ]; then
	BOLD="$ESC[1m"
	DIM="$ESC[2m"
	GREEN="$ESC[32m"
	RED="$ESC[31m"
	RESET="$ESC[0m"
else
	BOLD="" DIM="" GREEN="" RED="" RESET=""
fi

die() {
	printf 'install: %s\n' "$1" >&2
	exit 1
}

# One prank script per line. A prank folder is named after its script, so the
# script and the assets it reads travel together.
scripts=$(find "$PRANK_DIR" -mindepth 1 -maxdepth 1 -type d | sort |
	while read -r dir; do
		script="$dir/$(basename "$dir").sh"
		if [ -f "$script" ]; then printf '%s\n' "$script"; fi
	done)
[ -n "$scripts" ] || die "no prank scripts found in $PRANK_DIR"
count=$(printf '%s\n' "$scripts" | wc -l | tr -d ' ')

script_at() { printf '%s\n' "$scripts" | sed -n "$1p"; }

slug_of() {
	name=$(basename "$1")
	printf '%s' "${name%.sh}"
}

# A `# prank-<field>:` header comment, falling back to the file name.
meta_of() {
	value=$(sed -n "s/^# prank-$2: *//p" "$1" | head -1)
	if [ -n "$value" ]; then
		printf '%s' "$value"
	else
		slug_of "$1"
	fi
}

is_installed() {
	sh "$1" installed >/dev/null 2>&1
}

# Selection state: one 0/1 character per prank.
states=$(awk -v n="$count" 'BEGIN { while (i++ < n) printf "0" }')
cursor=1

state_at() { printf '%s' "$states" | cut -c"$1"; }

set_state() {
	head=""
	[ "$1" -gt 1 ] && head=$(printf '%s' "$states" | cut -c"1-$(($1 - 1))")
	tail=""
	[ "$1" -lt "$count" ] && tail=$(printf '%s' "$states" | cut -c"$(($1 + 1))-")
	states="$head$2$tail"
}

toggle() {
	if [ "$(state_at "$1")" = 1 ]; then set_state "$1" 0; else set_state "$1" 1; fi
}

selected_count() {
	printf '%s' "$states" | tr -cd 1 | wc -c | tr -d ' '
}

# What is installed right now, as a 0/1 string — the baseline the menu starts
# from and the thing the chosen state gets diffed against.
installed_states() {
	i=1
	while [ "$i" -le "$count" ]; do
		if is_installed "$(script_at "$i")"; then printf 1; else printf 0; fi
		i=$((i + 1))
	done
}

was_installed() { printf '%s' "$initial" | cut -c"$1"; }

cmd_list() {
	i=1
	while [ "$i" -le "$count" ]; do
		script=$(script_at "$i")
		printf '%-16s %s\n' "$(slug_of "$script")" "$(meta_of "$script" summary)"
		i=$((i + 1))
	done
}

draw() {
	i=1
	while [ "$i" -le "$count" ]; do
		script=$(script_at "$i")

		if [ "$(state_at "$i")" = 1 ]; then box="[${GREEN}x${RESET}]"; else box="[ ]"; fi
		if [ "$i" -eq "$cursor" ]; then pointer="${BOLD}>${RESET}"; else pointer=" "; fi

		# The tag spells out what enter will do to this line.
		tag=""
		case "$(was_installed "$i")$(state_at "$i")" in
		11) tag=" ${DIM}(installed)${RESET}" ;;
		10) tag=" ${RED}(will be removed)${RESET}" ;;
		01) tag=" ${GREEN}(will be installed)${RESET}" ;;
		esac

		printf '%s[2K %s %s %s%s\n' "$ESC" "$pointer" "$box" \
			"$(meta_of "$script" name)" "$tag"
		printf '%s[2K       %s%s%s\n' "$ESC" "$DIM" "$(meta_of "$script" summary)" "$RESET"
		i=$((i + 1))
	done
}

restore_terminal() {
	[ -n "${stty_saved:-}" ] && stty "$stty_saved" 2>/dev/null
	printf '%s[?25h' "$ESC"
}

# Read a single keypress, keeping the exact byte that came in. The X sentinel
# survives command substitution stripping trailing newlines.
read_key() {
	key=$(dd bs=1 count=1 2>/dev/null; printf X)
	key=${key%X}
	# Arrow keys arrive as ESC [ A and friends; keep only the final letter.
	if [ "$key" = "$ESC" ]; then
		rest=$(dd bs=1 count=2 2>/dev/null; printf X)
		key="$ESC${rest%X}"
	fi
}

run_prank() {
	printf '%s==> %s%s\n' "$BOLD" "$(meta_of "$1" name)" "$RESET"
	# One prank going wrong must not take the rest of the batch down.
	if sh "$1" "$2"; then
		:
	else
		printf '%s!! %s failed to %s%s\n' \
			"$BOLD" "$(slug_of "$1")" "$2" "$RESET" >&2
	fi
	printf '\n'
}

# Install what got selected, remove what got deselected, leave the rest alone.
apply_changes() {
	printf '\n'
	changed=0
	i=1
	while [ "$i" -le "$count" ]; do
		case "$(was_installed "$i")$(state_at "$i")" in
		01)
			run_prank "$(script_at "$i")" install
			changed=1
			;;
		10)
			run_prank "$(script_at "$i")" uninstall
			changed=1
			;;
		esac
		i=$((i + 1))
	done
	if [ "$changed" -eq 0 ]; then
		printf 'Nothing to change.\n'
	fi
	return 0
}

install_named() {
	printf '\n'
	i=1
	while [ "$i" -le "$count" ]; do
		if [ "$(state_at "$i")" = 1 ]; then
			run_prank "$(script_at "$i")" install
		fi
		i=$((i + 1))
	done
	printf '%sRemove any prank again with: sh prank/<name>/<name>.sh uninstall%s\n' \
		"$DIM" "$RESET"
	return 0
}

cmd_interactive() {
	[ -t 0 ] || die "not a terminal — pass prank names instead, e.g. sh install.sh $(slug_of "$(script_at 1)")"

	# The menu starts from reality: what is ticked is what is installed, so
	# unticking something is how you remove it.
	initial=$(installed_states)
	states=$initial

	printf '%sPick your pranks%s  %sup/down move, space ticks, enter applies, q quits%s\n' \
		"$BOLD" "$RESET" "$DIM" "$RESET"
	printf '%sTicked pranks are installed — untick one to remove it.%s\n\n' \
		"$DIM" "$RESET"

	stty_saved=$(stty -g)
	trap 'restore_terminal; exit 130' INT TERM
	trap 'restore_terminal' EXIT
	stty -echo -icanon
	printf '%s[?25l' "$ESC"

	draw
	while :; do
		read_key
		case $key in
		"$ESC[A" | k) [ "$cursor" -gt 1 ] && cursor=$((cursor - 1)) || cursor=$count ;;
		"$ESC[B" | j) [ "$cursor" -lt "$count" ] && cursor=$((cursor + 1)) || cursor=1 ;;
		' ') toggle "$cursor" ;;
		a)
			# Tick everything, or clear it all if everything is ticked already.
			if [ "$(selected_count)" -eq "$count" ]; then fill=0; else fill=1; fi
			i=1
			while [ "$i" -le "$count" ]; do
				set_state "$i" "$fill"
				i=$((i + 1))
			done
			;;
		r) states=$initial ;;
		q) restore_terminal; printf 'Nothing changed.\n'; return 0 ;;
		"")
			# Empty read means stdin closed under us; never take that as consent.
			restore_terminal
			printf 'Input ended, nothing changed.\n'
			return 0
			;;
		"$NL" | "$CR")
			restore_terminal
			apply_changes
			return 0
			;;
		esac
		# Two printed lines per prank, so step back over both.
		printf '%s[%dA' "$ESC" "$((count * 2))"
		draw
	done
}

# Names on the command line skip the menu entirely.
cmd_install_named() {
	for wanted in "$@"; do
		found=0
		i=1
		while [ "$i" -le "$count" ]; do
			if [ "$(slug_of "$(script_at "$i")")" = "$wanted" ]; then
				set_state "$i" 1
				found=1
			fi
			i=$((i + 1))
		done
		[ "$found" -eq 1 ] || die "no such prank '$wanted' — try: sh install.sh --list"
	done
	install_named
}

case "${1:---interactive}" in
--interactive) cmd_interactive ;;
--list | -l) cmd_list ;;
--help | -h) awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0" ;;
-*) die "unknown option '$1' — use --list or --help" ;;
*) cmd_install_named "$@" ;;
esac

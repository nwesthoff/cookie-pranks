#!/bin/sh
# prank-name: Cookie wallpaper
# prank-summary: The desktop background becomes a tray of fresh cookies
#
#   sh prank/cookie-wallpaper/cookie-wallpaper.sh             set the cookies as wallpaper
#   sh prank/cookie-wallpaper/cookie-wallpaper.sh status      show the current desktop
#   sh prank/cookie-wallpaper/cookie-wallpaper.sh installed   exit 0 if set, 1 if not
#   sh prank/cookie-wallpaper/cookie-wallpaper.sh uninstall   put the old desktop back
#
# Configuration (environment variables, all optional):
#   PRANK_WALLPAPER   image to put on the desktop   (default: image.jpg next to this script)

set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

WALLPAPER=${PRANK_WALLPAPER:-"$SCRIPT_DIR/image.jpg"}

STATE_DIR="$HOME/Library/Application Support/cookie-prank"
BACKUP="$STATE_DIR/wallpaper-index.plist"
# Where macOS keeps the desktop configuration for every space and display.
INDEX="$HOME/Library/Application Support/com.apple.wallpaper/Store/Index.plist"

die() {
	printf 'cookie-wallpaper: %s\n' "$1" >&2
	exit 1
}

# The picture on the desktop right now. A folder comes back when the desktop
# is a rotating album rather than a single image.
current_wallpaper() {
	osascript -l JavaScript -e '
		ObjC.import("AppKit");
		var screen = $.NSScreen.mainScreen;
		var url = $.NSWorkspace.sharedWorkspace.desktopImageURLForScreen(screen);
		url.isNil() ? "" : ObjC.unwrap(url.path);
	' 2>/dev/null
}

# The path travels in the environment, so spaces and quotes in it stay intact.
set_wallpaper() {
	PRANK_TARGET=$1 osascript -l JavaScript -e '
		ObjC.import("AppKit");
		var target = $.NSProcessInfo.processInfo.environment.objectForKey("PRANK_TARGET");
		var url = $.NSURL.fileURLWithPath(target);
		var workspace = $.NSWorkspace.sharedWorkspace;
		var screens = $.NSScreen.screens;
		for (var i = 0; i < screens.count; i++) {
			var error = $();
			var ok = workspace.setDesktopImageURLForScreenOptionsError(
				url, screens.objectAtIndex(i), $(), error);
			if (!ok) {
				throw new Error("the desktop image was refused");
			}
		}
	' >/dev/null || die "could not set the desktop image — is $1 a readable image?"
}

cmd_install() {
	[ -f "$WALLPAPER" ] || die "no image at $WALLPAPER"

	mkdir -p "$STATE_DIR"
	# Save the whole configuration rather than just the current picture: it is
	# the only thing that brings back a rotating album, a dynamic desktop or a
	# per-display setup exactly as it was. Installing twice must not overwrite
	# the saved copy with the cookies.
	if [ ! -f "$BACKUP" ] && [ -f "$INDEX" ]; then
		cp "$INDEX" "$BACKUP"
	fi

	set_wallpaper "$WALLPAPER"

	printf 'The desktop is now %s\n' "$WALLPAPER"
	if [ -f "$BACKUP" ]; then
		printf 'The previous desktop is saved in %s\n' "$BACKUP"
	fi
	printf 'Keep this folder where it is — the desktop reads the image from disk.\n'
	printf 'Undo with: sh %s uninstall\n' "$0"
}

cmd_uninstall() {
	if [ ! -f "$BACKUP" ]; then
		printf 'No saved desktop to put back — pick one in System Settings.\n'
		return 0
	fi

	mkdir -p "$(dirname "$INDEX")"
	cp "$BACKUP" "$INDEX"
	rm -f "$BACKUP"
	# WallpaperAgent owns that file and only rereads it on startup, so the old
	# desktop stays invisible until the agent comes back.
	killall WallpaperAgent 2>/dev/null || true

	printf 'Put the previous desktop back.\n'
}

cmd_installed() {
	[ "$(current_wallpaper)" = "$WALLPAPER" ]
}

cmd_status() {
	current=$(current_wallpaper)
	if [ -z "$current" ]; then
		printf 'The desktop image could not be read.\n'
		return 0
	fi

	if [ "$current" = "$WALLPAPER" ]; then
		printf 'Cookies are on the desktop.\n'
	else
		printf 'The desktop is %s\n' "$current"
	fi
	if [ -f "$BACKUP" ]; then
		printf 'A previous desktop is saved in %s\n' "$BACKUP"
	fi
	return 0
}

case "${1:-install}" in
install) cmd_install ;;
status) cmd_status ;;
installed) cmd_installed ;;
uninstall) cmd_uninstall ;;
*) die "unknown command '$1' — use install, status, installed or uninstall" ;;
esac

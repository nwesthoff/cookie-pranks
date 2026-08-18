# cookie-prank

Harmless pranks for an unattended, unlocked Mac. Clone, pick, walk away.

```sh
git clone <this-repo> && cd cookie-prank
sh install.sh
```

```
Pick your pranks  up/down move, space ticks, enter applies, q quits
Ticked pranks are installed — untick one to remove it.

 > [x] Cookie wallpaper (installed)
       The desktop background becomes a tray of fresh cookies
   [ ] Sound effects
       A random sound plays at random moments during working hours
```

Every prank is a folder in `prank/` holding one POSIX shell script and the
assets that script needs, installs nothing outside the current user's account,
and undoes itself with `uninstall`.

## The installer

```sh
sh install.sh                    # pick from the menu
sh install.sh sound-effects      # install by name, no prompting
sh install.sh --list             # what is available
```

Passing names only ever installs — it never removes anything you did not
mention. Removing is the menu's job, or the prank's own `uninstall`.

The menu opens with the installed pranks already ticked, so what you see is the
desired end state rather than a queue. Tick a prank to install it, untick one to
remove it, and enter applies exactly that difference — anything you leave alone
is not touched, not reinstalled. Each line says what enter will do to it:

```
 > [x] Sound effects (installed)            already on, staying on
   [x] Cookie wallpaper (will be installed) newly ticked
   [ ] Keyboard chaos (will be removed)     was on, now unticked
```

Arrow keys or `j`/`k` move, space ticks, `a` ticks all (or clears all), `r`
resets to what is actually installed, enter applies, `q` quits. Enter with
nothing changed says so and does nothing. One prank failing does not stop the
rest of the batch.

The menu builds itself from `prank/<name>/<name>.sh`, so a new prank shows up as
soon as its folder is there and the script has the two header comments the
others have:

```
prank/
├── cookie-wallpaper/
│   ├── cookie-wallpaper.sh
│   └── image.jpg
├── slack-shoutout/
│   ├── slack-shoutout.sh
│   └── task-index.js
└── sound-effects/
    ├── sound-effects.sh
    └── sounds/
```

```sh
# prank-name: Sound effects
# prank-summary: A random sound plays at random moments during working hours
```

Anything else in the folder is the prank's own business — sounds, images,
whatever it needs — which keeps a prank removable by deleting one directory.

A prank script installs itself when run with no arguments, and should support
`uninstall` plus an `installed` check that exits 0 when active.

## Pranks

### `prank/cookie-wallpaper/`

Puts `prank/cookie-wallpaper/image.jpg` — a tray of fresh cookies — on every
display.

```sh
sh prank/cookie-wallpaper/cookie-wallpaper.sh              # cookies on the desktop
sh prank/cookie-wallpaper/cookie-wallpaper.sh status       # what the desktop is now
sh prank/cookie-wallpaper/cookie-wallpaper.sh installed    # exit 0 if set, 1 if not
sh prank/cookie-wallpaper/cookie-wallpaper.sh uninstall    # put the old desktop back
```

Swap in your own picture by replacing `image.jpg`, or point at one somewhere
else:

```sh
PRANK_WALLPAPER=~/Pictures/cat.jpg sh prank/cookie-wallpaper/cookie-wallpaper.sh
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `PRANK_WALLPAPER` | `prank/cookie-wallpaper/image.jpg` | Image to put on the desktop |

Notes for the victim's Mac:

- Uninstall restores the desktop from a copy of the whole macOS wallpaper
  configuration, saved to `~/Library/Application Support/cookie-prank/` at
  install time. That copy is what brings back a rotating album, a dynamic
  desktop, or a different picture per display — a remembered file name could
  not. Installing twice does not overwrite it.
- The desktop reads the image from disk, so moving or deleting the clone while
  the prank is installed leaves them staring at a blank background. Uninstall
  first, then move.
- Restoring quits `WallpaperAgent` so it rereads its configuration. It comes
  straight back on its own; the desktop flickers once.

### `prank/slack-shoutout/`

Registers a Claude scheduled task ("Task" in Claude Desktop / Claude Code)
that fires every other day and posts a fresh, over-the-top shoutout to
`#shoutouts` about leaving the computer unlocked — cookies owed. Claude writes
new wording every time; nothing here contains the actual message text.

```sh
sh prank/slack-shoutout/slack-shoutout.sh              # schedule the shoutout
sh prank/slack-shoutout/slack-shoutout.sh status       # where it is scheduled
sh prank/slack-shoutout/slack-shoutout.sh installed    # exit 0 if scheduled, 1 if not
sh prank/slack-shoutout/slack-shoutout.sh uninstall    # remove it everywhere it was added
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `PRANK_TASK_ID` | `cookie-prank-shoutout` | Scheduled task id/slug |
| `PRANK_TASK_NAME` | `Cookie Prank Shoutout` | Display name in the Tasks UI |
| `PRANK_CRON` | `43 10 */2 * *` | 5-field cron, local time |
| `PRANK_SLACK_CHANNEL_ID` | `C03NBRPBWV9` | Slack channel to post to (`#shoutouts`) |
| `PRANK_SLACK_TOOL` | `mcp__claude_ai_Slack__slack_send_message` | Slack send-message tool name |
| `PRANK_SESSIONS_DIR` | `~/Library/Application Support/Claude/claude-code-sessions` | Where Claude keeps its account/org directories |

Notes for the victim's Mac:

- Requires Claude Desktop or Claude Code to already have a Slack connection
  and scheduled tasks enabled (on by default) — the installer registers the
  task in every account/org directory it finds under `PRANK_SESSIONS_DIR`,
  and errors out if there are none.
- `*/2` on the day-of-month field means "every other day" drifts by one at
  month boundaries (e.g. the 31st is followed by the 1st) — a minor, harmless
  wobble in an otherwise unpredictable joke.
- The install only ever appends its own task by id and only ever removes that
  same id — other scheduled tasks in the same account are left untouched, and
  a `scheduled-tasks.json` that doesn't parse as expected is skipped rather
  than rewritten.
- The Slack send-message tool is pre-approved on the task itself so the post
  doesn't sit waiting on a permission prompt nobody is there to answer.
- The first time a `scheduled-tasks.json` is touched, its prior contents are
  saved to a sibling `.bak` — an empty `.bak` means there was no file there
  yet. It is written exactly once (never overwritten by a later reinstall,
  even after our own task has been added) and never restored automatically by
  `uninstall` (a blind restore could delete a real task added in the
  meantime); it is a manual safety net, not an undo button. Delete it
  yourself once you're confident.

### `prank/sound-effects/`

Plays a random sound file at random moments during working hours, via cron.

```sh
sh prank/sound-effects/sound-effects.sh              # install a schedule for today
sh prank/sound-effects/sound-effects.sh play         # play one sound now, to check the volume
sh prank/sound-effects/sound-effects.sh status       # what is scheduled, plus recent plays
sh prank/sound-effects/sound-effects.sh installed    # exit 0 if scheduled, 1 if not
sh prank/sound-effects/sound-effects.sh uninstall    # remove it all
```

Put your sound files in `prank/sound-effects/sounds/` — `.mp3`, `.m4a`, `.wav`,
`.aiff`. Each play picks one at random, so a handful of files goes a long way.

Four sounds a day, Mon–Fri between 09:15 and 17:15 by default. The window is cut
into equal blocks with one sound at a random minute inside each, so the times are
unpredictable without ever landing three in a row. A cron entry at the top of the
window re-rolls the times each morning, so no two days repeat.

Tune it with environment variables:

```sh
PRANK_COUNT=8 PRANK_START=08:30 PRANK_END=18:00 sh prank/sound-effects/sound-effects.sh
```

| Variable | Default | Meaning |
| --- | --- | --- |
| `PRANK_SOUNDS_DIR` | `prank/sound-effects/sounds` | Folder to pick sound files from |
| `PRANK_COUNT` | `4` | Sounds per day |
| `PRANK_START` | `09:15` | Start of the window, `HH:MM` |
| `PRANK_END` | `17:15` | End of the window, `HH:MM` |
| `PRANK_DAYS` | `1-5` | Cron day-of-week spec (`1-5` is Mon–Fri) |
| `PRANK_VOLUME` | `1` | `afplay` volume; `1` is normal, higher is louder |

Plays are logged to `~/Library/Logs/cookie-prank.log`.

Notes for the victim's Mac:

- The cron entries live in **their** user crontab, and the script only ever
  touches lines between its own markers — anything else in there is left alone.
- Keep the clone somewhere cron can read. macOS blocks `cron` from
  `~/Desktop`, `~/Documents` and `~/Downloads` unless `/usr/sbin/cron` has Full
  Disk Access — `~/src` or `/tmp` needs no such permission.
- If `crontab` itself reports `Operation not permitted`, the terminal app needs
  Full Disk Access in System Settings → Privacy & Security.
- Sound comes out of whatever output device is selected, at the system volume. A
  muted Mac plays nothing, and `play` is the quickest way to find that out.

## Being a good sport

Pick something silly, keep it to colleagues who will laugh, and clean up after
yourself:

```sh
sh prank/cookie-wallpaper/cookie-wallpaper.sh uninstall
sh prank/sound-effects/sound-effects.sh uninstall
sh prank/slack-shoutout/slack-shoutout.sh uninstall
```

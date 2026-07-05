# screentime-backup

Weekly local snapshots of macOS Screen Time data, run by a `launchd` LaunchAgent.

Captures, every Sunday at 05:00:

- `knowledgeC.db` — the legacy Screen Time / device-activity store.
- `RMAdminStore-{Local,Cloud}.sqlite` — ScreenTimeAgent's device/settings
  registry (usage tables are unused on current macOS).
- `device-activity.tar.gz` — ScreenTimeAgent's DeviceActivity summaries: per-device
  Daily/Hourly/Weekly plists with total screen time (incl. home-screen dwell),
  per-app durations, pickups, notification counts, and web-domain usage. This is
  what Settings → Screen Time renders for *Share Across Devices* data; Apple only
  retains ~4 weeks, so these snapshots preserve history.
- A curated subset of `~/Library/Biome/streams` — the modern cross-device event
  data (app focus, activity, media/web usage, now-playing, wifi/bluetooth).

Backups land in a dated folder per run — `~/Documents/screen-time-backups/<YYYY-MM-DD>/`
(e.g. `2026-06-27/knowledgeC.db.gz`, `rmadmin-local.db.gz`, `rmadmin-cloud.db.gz`,
`device-activity.tar.gz`, `biome-streams.tar.gz`). The run log is `~/Library/Logs/screentime-backup.log`.

## Layout

```
screentime-backup/
├── screentime-backup.sh                      # the backup logic (source of truth)
├── com.alexmiller.screentime-backup.plist    # LaunchAgent definition
├── bundle/Info.plist                         # template for the .app bundle
├── justfile                                  # install / run / status / logs / uninstall
└── README.md
```

`just install` assembles a self-contained app at
`~/Applications/ScreenTimeBackup.app`, whose **main executable is the backup
script itself** (`Contents/MacOS/screentime-backup`, copied from
`screentime-backup.sh`). The LaunchAgent runs that bundle.

## Why an .app bundle (and why signed)

The script reads TCC-protected data (`knowledgeC.db`, the ScreenTimeAgent
stores, Biome streams), which requires **Full Disk Access**. macOS grants Full
Disk Access to a *code identity*, not to a loose `.sh` file — so the logic is
wrapped in a signed `.app` whose identity holds the grant.

The bundle is signed with an **Apple Development certificate**. Because TCC
matches the grant by the signing certificate rather than the content hash,
re-signing an edited script with the same cert **keeps Full Disk Access** — you
can change the logic and reinstall without re-granting.

## Usage

```sh
just install     # build + sign the app, install & load the LaunchAgent
just run         # trigger a backup now (via launchd, so it has Full Disk Access)
just status      # load state, schedule, and the last run from the log
just logs        # follow the log
just uninstall   # remove the LaunchAgent and the app (backups/log kept)
```

Editing workflow: change `screentime-backup.sh`, then `just install` to ship it
into the bundle and reload the agent.

## Manual step: grant Full Disk Access (once)

Full Disk Access cannot be granted programmatically (Apple blocks it). After the
**first** `just install` — and again only if the signing certificate is rotated
(roughly yearly) — grant it once:

1. Open **System Settings → Privacy & Security → Full Disk Access**.
2. Click **+**, navigate to `~/Applications/ScreenTimeBackup.app`, add it, and
   ensure its toggle is **on**. If an older entry for the app is present, remove
   it first so the new identity is the one that's authorized.
3. Verify: `just run && just logs` — a healthy run logs `backup OK` lines and
   `=== run end ===` with no `cannot read` error.

## Schedule

`StartCalendarInterval` — every **Sunday at 05:00**. Unlike a rolling
`StartInterval`, a slot missed while the Mac is asleep/off fires once on the next
wake instead of silently drifting a full week out. To change the cadence, edit
`com.alexmiller.screentime-backup.plist` and re-run `just install`.

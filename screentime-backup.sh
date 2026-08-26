#!/bin/zsh
# Weekly snapshot of macOS Screen Time / knowledgeC.db.
# Triggered by ~/Library/LaunchAgents/com.alexmiller.screentime-backup.plist
# Requires Full Disk Access for the executing process (zsh and/or sqlite3).

set -euo pipefail

BACKUP_DIR="$HOME/Documents/screen-time-backups"
SOURCE_DB="$HOME/Library/Application Support/Knowledge/knowledgeC.db"
LOG_FILE="$HOME/Library/Logs/screentime-backup.log"
DATE="$(/bin/date +%Y-%m-%d)"
TS="$(/bin/date '+%Y-%m-%d %H:%M:%S')"
# One folder per run, named by date; filenames drop the (now-redundant) date.
# STB_DIR_SUFFIX (e.g. "-macbook") keeps multiple machines writing into the
# same iCloud-synced BACKUP_DIR from colliding on a same-day run.
RUN_DIR="$BACKUP_DIR/${DATE}${STB_DIR_SUFFIX:-}"
DEST="$RUN_DIR/knowledgeC.db"

mkdir -p "$RUN_DIR" "$(/usr/bin/dirname "$LOG_FILE")"

log() { print -r -- "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

log "=== run start ==="

if [[ ! -r "$SOURCE_DB" ]]; then
  log "ERROR: cannot read $SOURCE_DB — grant Full Disk Access to /bin/zsh and/or this script in System Settings → Privacy & Security."
  exit 1
fi

# Nudge usageeventsd so it re-registers with CloudKit and pulls any pending iPhone events.
# Undocumented and best-effort: not a true 'sync now' trigger, but commonly used.
if /usr/bin/pkill -x usageeventsd 2>/dev/null; then
  log "bounced usageeventsd, sleeping 30s to let it respawn and reconcile"
  /bin/sleep 30
else
  log "usageeventsd was not running, skipping bounce"
  /bin/sleep 5
fi

# Online consistent snapshot of the live SQLite DB (handles WAL correctly).
if /usr/bin/sqlite3 "$SOURCE_DB" ".backup '$DEST'"; then
  /bin/rm -f "${DEST}-wal" "${DEST}-shm"  # drop WAL/SHM sidecars left beside the .backup copy
  /usr/bin/gzip -f "$DEST"
  SIZE=$(/usr/bin/du -h "${DEST}.gz" | /usr/bin/awk '{print $1}')
  log "backup OK: ${DEST}.gz (${SIZE})"
else
  log "ERROR: sqlite3 .backup failed for knowledgeC"
  exit 1
fi

# ScreenTimeAgent's RMAdminStore — the real per-app/device aggregation, including
# data synced from iPhone via 'Share Across Devices'. Path uses the per-user
# darwin temp folder hash, resolved dynamically.
USER_DIR="$(/usr/bin/getconf DARWIN_USER_DIR)"
ST_STORE="${USER_DIR}com.apple.ScreenTimeAgent/Store"

for VARIANT in Local Cloud; do
  SRC="${ST_STORE}/RMAdminStore-${VARIANT}.sqlite"
  DST="$RUN_DIR/rmadmin-$(/usr/bin/tr '[:upper:]' '[:lower:]' <<<"$VARIANT").db"
  if [[ ! -r "$SRC" ]]; then
    log "WARN: ${VARIANT} store not readable at $SRC — skipping"
    continue
  fi
  if /usr/bin/sqlite3 "$SRC" ".backup '$DST'"; then
    /usr/bin/gzip -f "$DST"
    SIZE=$(/usr/bin/du -h "${DST}.gz" | /usr/bin/awk '{print $1}')
    log "backup OK: ${DST}.gz (${SIZE})"
  else
    log "ERROR: sqlite3 .backup failed for RMAdminStore-${VARIANT}"
  fi
done

# DeviceActivity summaries — Apple's official per-device usage rollups (Daily/
# Hourly/Weekly plists): total screen time incl. home-screen dwell, per-app
# durations, pickups, notification counts, and web-domain usage. This is the
# data the Settings → Screen Time pane renders; retention is only ~4 weeks,
# so the weekly snapshot is what preserves history.
DA_DIR="${ST_STORE}/Library/com.apple.DeviceActivity"
DA_OUT="$RUN_DIR/device-activity.tar.gz"
if [[ -d "$DA_DIR" ]]; then
  if /usr/bin/tar -czf "$DA_OUT" -C "${ST_STORE}/Library" com.apple.DeviceActivity 2>/dev/null; then
    SIZE=$(/usr/bin/du -h "$DA_OUT" | /usr/bin/awk '{print $1}')
    log "backup OK: $DA_OUT ($SIZE)"
  else
    log "ERROR: tar failed for device activity"
  fi
else
  log "WARN: DeviceActivity dir not found at $DA_DIR, skipping"
fi

# Biome streams — the actual modern home of cross-device event data. Each stream
# has local/ (Mac) and remote/<device-uuid>/ (iPhone, Watch, etc.) subdirs of
# append-only SEGB binary log files. We capture a curated 'Screen Time'-shaped
# subset; full ~/Library/Biome/streams is ~1GB and mostly Siri analytics noise.
BIOME_STREAMS="$HOME/Library/Biome/streams/restricted"
BIOME_OUT="$RUN_DIR/biome-streams.tar.gz"
CURATED_STREAMS=(
  App.InFocus
  App.Activity
  App.MediaUsage
  App.WebUsage
  App.Intent
  Media.NowPlaying
  Device.Wireless.Bluetooth
  Wifi.Connection
)

EXISTING_STREAMS=()
for s in "${CURATED_STREAMS[@]}"; do
  if [[ -d "$BIOME_STREAMS/$s" ]]; then
    EXISTING_STREAMS+=("$s")
  fi
done

if (( ${#EXISTING_STREAMS[@]} > 0 )); then
  if /usr/bin/tar -czf "$BIOME_OUT" -C "$BIOME_STREAMS" "${EXISTING_STREAMS[@]}" 2>/dev/null; then
    SIZE=$(/usr/bin/du -h "$BIOME_OUT" | /usr/bin/awk '{print $1}')
    log "backup OK: $BIOME_OUT ($SIZE, ${#EXISTING_STREAMS[@]} streams)"
  else
    log "ERROR: tar failed for biome streams"
  fi
else
  log "WARN: none of the curated biome streams exist, skipping"
fi

log "=== run end ==="

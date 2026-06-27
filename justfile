# screentime-backup — build, install, and manage the Screen Time backup LaunchAgent.
# The app is self-contained: `screentime-backup.sh` is shipped as the bundle's
# main executable, code-signed so Full Disk Access survives edits.

set shell := ["zsh", "-cu"]

app        := "/Users/alexmiller/Applications/ScreenTimeBackup.app"
label      := "com.alexmiller.screentime-backup"
plist_src  := "com.alexmiller.screentime-backup.plist"
plist_dst  := "/Users/alexmiller/Library/LaunchAgents/com.alexmiller.screentime-backup.plist"
log        := "/Users/alexmiller/Library/Logs/screentime-backup.log"
# Sign with this identity so TCC matches the grant by certificate (stable across
# edits) rather than by content hash. Re-signing an edited script with the same
# cert keeps Full Disk Access. `security find-identity -v -p codesigning` to list.
signing_id := "Apple Development: redacted-usr@gmail.com (REDACTED)"

# List available recipes.
default:
    @just --list

# Build & sign the .app bundle, install the LaunchAgent, and (re)load it.
install:
    #!/usr/bin/env zsh
    set -euo pipefail
    app="{{app}}"; contents="$app/Contents"
    echo "==> Building bundle at $app"
    rm -rf "$app"
    mkdir -p "$contents/MacOS"
    cp bundle/Info.plist "$contents/Info.plist"
    cp screentime-backup.sh "$contents/MacOS/screentime-backup"
    chmod +x "$contents/MacOS/screentime-backup"
    echo "==> Signing with: {{signing_id}}"
    codesign --force --identifier "{{label}}" --sign "{{signing_id}}" --timestamp=none "$app"
    codesign --verify --verbose "$app"
    echo "==> Installing LaunchAgent"
    cp "{{plist_src}}" "{{plist_dst}}"
    uid=$(id -u)
    launchctl bootout "gui/$uid/{{label}}" 2>/dev/null || true
    launchctl bootstrap "gui/$uid" "{{plist_dst}}"
    echo
    echo "Installed and loaded."
    echo "If Full Disk Access is not yet granted to this exact bundle, grant it once:"
    echo "  System Settings > Privacy & Security > Full Disk Access > [ + ] > $app"
    echo "Then verify with:  just run && just logs"

# Trigger a backup now, through launchd (so it runs with the app's FDA identity).
run:
    #!/usr/bin/env zsh
    set -euo pipefail
    launchctl kickstart -k "gui/$(id -u)/{{label}}"
    echo "Backup kicked off (~35-40s). Watch it with: just logs"

# Show the agent's load state, schedule, and the last run from the log.
status:
    #!/usr/bin/env zsh
    set -euo pipefail
    launchctl print "gui/$(id -u)/{{label}}" 2>/dev/null \
        | grep -iE "state =|runs =|last exit|program =" || echo "agent not loaded"
    echo "--- last log lines ---"
    tail -n 15 "{{log}}" 2>/dev/null || echo "(no log yet)"

# Follow the backup log.
logs:
    tail -n 40 -f "{{log}}"

# Remove the LaunchAgent and the .app. Leaves backups and the log intact.
uninstall:
    #!/usr/bin/env zsh
    set -euo pipefail
    uid=$(id -u)
    launchctl bootout "gui/$uid/{{label}}" 2>/dev/null || true
    rm -f "{{plist_dst}}"
    rm -rf "{{app}}"
    echo "Uninstalled. Backups (~/Documents/ScreenTimeBackups) and the log are untouched."

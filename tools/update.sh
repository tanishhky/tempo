#!/usr/bin/env bash
# Update Tempo to the latest version in this clone and reinstall it. Your data is kept.
#
#   ./tools/update.sh               back up, pull, test, build, install
#   ./tools/update.sh --no-install  the same, but stop after building
#
# Your history is never moved, rewritten or deleted by this script. Before anything else changes,
# the session log, activities, journal and settings are copied into a timestamped folder under
# ~/Library/Application Support/Tempo/backups. The last ten backups are kept.
set -euo pipefail
cd "$(dirname "$0")/.."

DATA="${TEMPO_DATA_DIR:-$HOME/Library/Application Support/Tempo}"
INSTALL=1
if [[ "${1:-}" == "--no-install" ]]; then INSTALL=0; fi

sessions_count() {
    if [[ -f "$DATA/sessions.jsonl" ]]; then wc -l < "$DATA/sessions.jsonl" | tr -d ' '; else echo 0; fi
}

# 1. Refuse to pull over local edits. Those would be the only copy of your changes to this code.
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "This clone has local edits to tracked files. Commit or stash them, then run this again." >&2
    echo "Your Tempo data was not touched." >&2
    exit 1
fi

# 2. Back up the data first. Copies only, so the originals stay where the app expects them.
stamp=$(date +%Y%m%d-%H%M%S)
backup="$DATA/backups/$stamp"
mkdir -p "$backup"
for file in sessions.jsonl activities.json journal.jsonl; do
    if [[ -f "$DATA/$file" ]]; then cp -p "$DATA/$file" "$backup/$file"; fi
done
defaults export me.tanishkyadav.tempo "$backup/settings.plist" 2>/dev/null || true
echo "Backed up your data to $backup"

# Keep the newest ten backups, remove older ones.
if [[ -d "$DATA/backups" ]]; then
    old=$(ls -1t "$DATA/backups" | tail -n +11 || true)
    for name in $old; do rm -rf "$DATA/backups/$name"; done
fi

before=$(sessions_count)

# 3. Fetch the new version. Fast-forward only, so a diverged branch stops here instead of merging silently.
if ! git pull --ff-only; then
    echo "Could not fast-forward this clone. Nothing was changed. Your data is in $backup." >&2
    exit 1
fi

# 4. Test before building. A failure stops the update and leaves the installed app as it was.
python3 -m unittest discover -s tools -p "test_*.py"
./tools/selftest.sh

# 5. Build, and install if asked. build.sh stops before installing if the compile fails.
if [[ "$INSTALL" == 1 ]]; then
    ./build.sh --install
else
    ./build.sh
fi

after=$(sessions_count)
echo "Sessions: $before before the update, $after after. Nothing was removed."
if (( after < before )); then
    echo "The session count went down. Your backup is in $backup. Please check before you continue." >&2
    exit 1
fi

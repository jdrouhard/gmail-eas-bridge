#!/bin/bash
set -euo pipefail

MAILDIR="${MAILDIR:-/data/maildir}"
DEBOUNCE="${MBSYNC_DEBOUNCE:-1}"

log() {
    echo "[maildir-watch] $*" >&2
}

if ! command -v inotifywait >/dev/null 2>&1; then
    log "ERROR: inotifywait not found"
    exit 1
fi

if [ ! -d "$MAILDIR" ]; then
    log "ERROR: Maildir does not exist: $MAILDIR"
    exit 1
fi

log "watching $MAILDIR"

inotifywait \
    --monitor \
    --recursive \
    --quiet \
    --event close_write \
    --event create \
    --event delete \
    --event moved_to \
    --event moved_from \
    --exclude '(^|/)(tmp|\.mbsyncstate.*|\.uidvalidity|dovecot\..*|dovecot-.*)$' \
    --format '%w%f' \
    "$MAILDIR" |
while IFS= read -r path; do
    log "Maildir changed: $path"

    while IFS= read -r -t "$DEBOUNCE" _; do
        :
    done

    log "running mbsync"
    /usr/local/bin/mbsync-wrapper || \
        log "mbsync failed; periodic cron pass remains as a safety net"
done

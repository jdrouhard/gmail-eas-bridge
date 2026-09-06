#!/bin/bash
set -euo pipefail

# --- PUID/PGID: remap the single "vmail" user/group, lscr.io-style --------
# Everything under /data (maildir, z-push state) and everything that
# reads/writes it (mbsync, goimapnotify, Dovecot's mail delivery, and
# php-fpm) runs as this one identity, so a bind-mounted host directory
# ends up owned by whatever UID/GID you tell it to.
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

CURRENT_UID="$(id -u vmail)"
CURRENT_GID="$(id -g vmail)"

if [ "$PGID" != "$CURRENT_GID" ]; then
    groupmod -o -g "$PGID" vmail
fi
if [ "$PUID" != "$CURRENT_UID" ]; then
    usermod -o -u "$PUID" vmail
fi

# Ownership of anything vmail already owns needs to follow the new IDs.
# (This is a fixed, known list rather than a filesystem-wide find, to
# avoid accidentally touching unrelated files that happen to share the
# old UID/GID.)
chown -R vmail:vmail \
    /home/vmail \
    /usr/share/z-push \
    /var/log/z-push \
    /usr/share/z-push/config.php \
    /usr/share/z-push/backend/imap/config.php \
    2>/dev/null || true

: "${GMAIL_USER:?GMAIL_USER must be set (your full Gmail address)}"

# Both secrets may come in as an env var OR as a mounted secret file -
# prefer the file if present, same pattern for both. There's no good
# reason to treat one credential more carefully than the other: anyone
# with ZPUSH_LOCAL_PASSWORD and network access to the EAS endpoint can
# read/send your mail just as fully as anyone with the Gmail password.
if [ -f /run/secrets/zpush_local_password ]; then
    ZPUSH_LOCAL_PASSWORD="$(cat /run/secrets/zpush_local_password)"
else
    : "${ZPUSH_LOCAL_PASSWORD:?Set ZPUSH_LOCAL_PASSWORD or mount /run/secrets/zpush_local_password}"
fi

if [ -f /run/secrets/gmail_app_password ]; then
    GMAIL_APP_PASSWORD="$(cat /run/secrets/gmail_app_password)"
else
    : "${GMAIL_APP_PASSWORD:?Set GMAIL_APP_PASSWORD or mount /run/secrets/gmail_app_password}"
    mkdir -p /run/secrets
    printf '%s' "$GMAIL_APP_PASSWORD" > /run/secrets/gmail_app_password
    # Only this self-written copy needs its perms fixed up - a
    # Docker/Compose-mounted secret is already world-readable (0444)
    # and its mount may not even be writable from in here.
    chown vmail:vmail /run/secrets/gmail_app_password
    chmod 600 /run/secrets/gmail_app_password
fi

export GMAIL_USER ZPUSH_LOCAL_PASSWORD GMAIL_APP_PASSWORD

render() {
    # $1 = template path, $2 = destination path, $3 = space-separated var names
    # shellcheck disable=SC2016
    vars=$(printf '${%s} ' $3)
    envsubst "$vars" < "$1" > "$2"
}

render /etc/dovecot/templates/10-auth.conf.template \
       /etc/dovecot/conf.d/10-auth.conf \
       'ZPUSH_LOCAL_PASSWORD'

render /etc/dovecot/templates/10-submission.conf.template \
       /etc/dovecot/conf.d/10-submission.conf \
       'GMAIL_USER GMAIL_APP_PASSWORD'
chmod 600 /etc/dovecot/conf.d/10-submission.conf /etc/dovecot/conf.d/10-auth.conf

render /etc/mbsync/mbsyncrc.template /etc/mbsync/mbsyncrc 'GMAIL_USER'
chmod 600 /etc/mbsync/mbsyncrc

render /etc/imapnotify/gmail.json.template /etc/imapnotify/gmail.json 'GMAIL_USER'
chmod 600 /etc/imapnotify/gmail.json

# Make sure the runtime dirs exist. Everything under /data - the one
# bind mount you're expected to provide - is owned by vmail (PUID:PGID).
# Only pay for a recursive chown when ownership doesn't already match
# (first run, or after you've changed PUID/PGID) - on a large synced
# mailbox a chown -R on every restart would be needlessly slow.
mkdir -p /data/maildir /data/zpush-state /var/log/z-push
VMAIL_UID="$(id -u vmail)"
if [ "$(stat -c '%u' /data)" != "$VMAIL_UID" ]; then
    echo "[entrypoint] fixing ownership of /data (first run or PUID/PGID changed - may take a while on a large mailbox)..."
    chown -R vmail:vmail /data
else
    chown vmail:vmail /data /data/maildir /data/zpush-state
fi

# goimapnotify/mbsync/php-fpm/dovecot's mail delivery all run as vmail.
chown vmail:vmail /etc/mbsync/mbsyncrc /etc/imapnotify/gmail.json

# Prime the maildir on first boot so z-push has something to serve
# immediately instead of waiting for the first IDLE event.
echo "[entrypoint] running initial mbsync pass..."
gosu vmail mbsync -c /etc/mbsync/mbsyncrc -a || echo "[entrypoint] initial mbsync failed - will retry on next IDLE event"

exec /usr/bin/supervisord -c /etc/supervisor/conf.d/stack.conf

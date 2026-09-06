# Gmail → ActiveSync bridge (z-push + Dovecot + mbsync + goimapnotify)

Single container running:

- **mbsync** - syncs Gmail IMAP ↔ a local Maildir (`/data/maildir`)
- **goimapnotify** - holds an IMAP IDLE connection open to Gmail and
  triggers `mbsync` whenever new mail arrives, instead of polling
- **Dovecot** - serves that Maildir over IMAP on `127.0.0.1:143`, and
  relays outgoing mail via its **submission** service on
  `127.0.0.1:587` to `smtp.gmail.com`
- **z-push** (`BackendIMAP`) + **nginx/php-fpm** - speaks ActiveSync to
  your iPhone, using the local Dovecot for both read and send

Nothing but nginx (port 80) is meant to be reachable from outside the
container - Dovecot only listens on loopback.

## Why this shape

z-push's plain **Maildir** backend has no send path at all, and asking
z-push's IMAP backend to talk to Gmail directly runs into real,
reported reliability problems on large/active mailboxes (folder-scan
inefficiency, loop/stall behavior) plus Gmail-specific IMAP quirks
(labels-as-folders, `[Gmail]/All Mail` UID duplication, throttling).
mbsync is much more battle-tested against Gmail specifically. So:
mbsync does the actual Gmail talking, and z-push only ever talks to a
small, well-behaved local Dovecot.

## Build

```
docker compose build
```

or plain Docker:

```
docker build -t gmail-eas-bridge .
```

## Configure

1. Enable 2FA on the Google account, then create an **App Password**:
   https://myaccount.google.com/apppasswords
2. `cp .env.example .env` and fill in `GMAIL_USER`.
3. Create both secret files:
   ```
   mkdir -p secrets
   echo -n 'xxxx xxxx xxxx xxxx' > secrets/gmail_app_password.txt   # the App Password
   echo -n 'something-long-and-random' > secrets/zpush_local_password.txt
   chmod 600 secrets/*.txt
   ```
   `zpush_local_password` is what your iPhone (and any other EAS
   device) authenticates against *this bridge* with - it's unrelated
   to your Gmail password, you're inventing it. Both live in
   `secrets/`, not `.env`, so they never show up in `docker inspect`
   or the container's visible environment - see the note in
   `.env.example` if you're not using `docker compose` and need the
   env-var fallback instead.
4. Put a TLS-terminating reverse proxy (Caddy, Traefik, nginx) in
   front of this container. iOS's ActiveSync client requires HTTPS in
   practice - don't expose port 80 directly.

## Run

```
docker compose up -d
```

On your iPhone: Settings → Mail → Accounts → Add Account → Microsoft
Exchange. Server = your reverse proxy's hostname, username = anything
(single-user bridge), password = `ZPUSH_LOCAL_PASSWORD`.

## Known rough edges / things to verify before relying on this

- **`PUID`/`PGID`** (default `1000`/`1000`) control the UID/GID of the
  single `vmail` user inside the container, lscr.io-style. That one
  user owns everything under `/data` and runs every process that
  touches it (mbsync, goimapnotify, Dovecot's mail delivery, and
  php-fpm - nginx itself still runs as `www-data` since it never
  touches `/data`). Set these in `.env` to match a user on your host
  (`id -u` / `id -g`) so `./data` ends up owned by someone you
  recognize instead of an arbitrary container-internal UID.
  Changing `PUID`/`PGID` after mail has already synced triggers a
  one-time recursive `chown` of `/data` on the next start, which can
  take a while on a large mailbox.
- **`config/zpush/config.php` and `imap.php` are the real stock z-push
  files, patched, not hand-written from scratch.** An earlier version
  of this stack shipped hand-written versions of both that only
  defined the handful of constants this stack cares about - z-push's
  core code reads dozens of others directly without `defined()`
  guards, so that approach hit fatal "undefined constant" errors at
  runtime. These are now the actual stock `src/config.php` and
  `src/backend/imap/config.php` from the Z-Hub/Z-Push repo's `develop`
  branch, each with a small number of lines patched (search for
  `// patched:` comments to see exactly what changed and why).
- **`IMAP_DISABLE_AUTHENTICATOR = 'PLAIN'`** works around a c-client
  (the library behind PHP's `imap_open()`) quirk: it hardcodes a
  refusal to send SASL `AUTH=PLAIN` over a connection it considers
  insecure - which loopback Dovecot always is, since it has no TLS at
  all - regardless of Dovecot's own `disable_plaintext_auth` setting.
  You'll see `SECURITY PROBLEM: insecure server advertised AUTH=PLAIN`
  in z-push's logs without this. Disabling that specific authenticator
  makes it fall back to the plain IMAP `LOGIN` command instead - same
  credentials, same lack of encryption (fine here, loopback-only),
  just a different code path that doesn't have this refusal built in.
- **Sent-mail duplication risk.** Gmail's SMTP auto-saves a copy of
  anything relayed through `smtp.gmail.com` into `[Gmail]/Sent Mail`
  server-side. This stack does *not* have z-push separately append
  sent mail locally - it relies on mbsync pulling that Gmail-side copy
  down on the next sync. If you find z-push's IMAP backend still
  appends a copy itself in whatever version you build, you'll get
  duplicates; check `IMAP_FOLDER_SENT` behavior for your checkout.
- **`[Gmail]/All Mail` is synced as `Archive`**, which means every
  Inbox (and Sent, etc.) message is duplicated locally: once under its
  normal folder, once again under Archive, with independent read/flag
  state between the two copies. That's how Gmail's IMAP actually
  models labels-as-folders, not a bug in this config. If you'd rather
  not pay that storage/state-sync cost, comment out the `gmail-archive`
  channel (and its line in `Group gmail`) in `mbsyncrc.template` and
  live without a synced Archive folder.
- **Dovecot submission relay auth** uses the plaintext
  `submission_relay_user`/`submission_relay_password` settings, which
  is the simple smarthost-relay approach for a fixed single account.
  Confirm this syntax is still current for whatever Dovecot version
  Debian bookworm ships when you build.
- **goimapnotify build**: there's no Debian package for it, so it's
  compiled from source in a build stage (`bamthomas/goimapnotify`).
  This needs outbound network access to GitHub at build time.
- This has been written out carefully but **not build-tested
  end-to-end** in this environment (no Docker daemon / restricted
  network here) - expect to fix a few small things (package names,
  exact config keys) on your first `docker build`.

## Files

```
Dockerfile
entrypoint.sh              # renders templates from env/secrets, starts supervisord
supervisord.conf           # runs dovecot, php-fpm, nginx, goimapnotify
docker-compose.yml
.env.example
config/
  zpush/config.php         # stock z-push config, patched (see file for // patched: markers)
  zpush/imap.php           # stock IMAP backend config, patched to point at local Dovecot
  nginx/zpush.conf         # nginx site config
  dovecot/dovecot.conf     # main Dovecot config (loopback-only)
  dovecot/conf.d/10-master.conf
  dovecot/templates/10-auth.conf.template        # rendered at runtime
  dovecot/templates/10-submission.conf.template  # rendered at runtime
  mbsync/mbsyncrc.template                       # rendered at runtime
  imapnotify/gmail.json.template                 # rendered at runtime
patches/
  imap-delete-no-trash-move.patch  # applied via `git apply` during the Docker build,
                                    # see "Delete vs Archive" above
```

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

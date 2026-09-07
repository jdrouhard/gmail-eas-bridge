# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1: build goimapnotify (no prebuilt Debian package exists)
# ---------------------------------------------------------------------------
FROM golang:1.23-bookworm AS gobuild

WORKDIR /src
RUN git clone --depth 1 https://gitlab.com/shackra/goimapnotify.git . \
    && go build -o /out/goimapnotify ./cmd/goimapnotify

# ---------------------------------------------------------------------------
# Stage 2: runtime image
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC

RUN apt-get update && apt-get install -y --no-install-recommends \
        dovecot-core dovecot-imapd dovecot-submissiond \
        isync \
        nginx-light \
        php-fpm php-imap php-intl php-xml php-mbstring \
        git supervisor gettext-base ca-certificates tzdata gosu passwd \
    && rm -rf /var/lib/apt/lists/* \
    && PHP_FPM_POOL=$(find /etc/php -name "www.conf" -path "*fpm*" | head -n1) \
    && sed -i "s|^listen = .*|listen = 127.0.0.1:9000|" "$PHP_FPM_POOL" \
    && sed -i "s|^user = .*|user = vmail|" "$PHP_FPM_POOL" \
    && sed -i "s|^group = .*|group = vmail|" "$PHP_FPM_POOL" \
    && sed -i "s|^;\?daemonize = .*|daemonize = no|" $(find /etc/php -name "php-fpm.conf" | head -n1) \
    && PHP_INI=$(find /etc/php -name "php.ini" -path "*fpm*" | head -n1) \
    && sed -i \
        -e "s|^memory_limit = .*|memory_limit = 512M|" \
        -e "s|^max_execution_time = .*|max_execution_time = 900|" \
        -e "s|^max_input_time = .*|max_input_time = 300|" \
        -e "s|^upload_max_filesize = .*|upload_max_filesize = 50M|" \
        -e "s|^post_max_size = .*|post_max_size = 50M|" \
        "$PHP_INI"

# --- single app/mail user, remapped to PUID/PGID at container start ---------
# (see entrypoint.sh) - this is the only user that ever touches /data.
# 1000:1000 is just the build-time default; entrypoint.sh remaps it.
RUN useradd -u 1000 -U -d /data/maildir -m -s /usr/sbin/nologin vmail

# --- z-push (community-maintained fork) -------------------------------------
ARG ZPUSH_REF=develop
# master is abandoned (last commit 2021) - develop is where all active
# work happens and what config/zpush/*.php were verified against. See
# README.md for the release/2.7 alternative if you want something more
# pinned than tracking develop's moving HEAD.
COPY patches/ /tmp/patches/
RUN git clone --depth 1 --branch ${ZPUSH_REF} https://github.com/Z-Hub/Z-Push.git /tmp/z-push \
    && git -C /tmp/z-push apply /tmp/patches/imap-delete-no-trash-move.patch \
    && git -C /tmp/z-push apply /tmp/patches/imap-idle-sink.patch \
    && git -C /tmp/z-push apply /tmp/patches/imap-header-parsing-improvements.patch \
    && git -C /tmp/z-push apply /tmp/patches/timezone-util-fix.patch \
    && mkdir -p /usr/share/z-push \
    && cp -r /tmp/z-push/src/* /usr/share/z-push/ \
    && rm -rf /tmp/z-push /tmp/patches \
    && mkdir -p /data/zpush-state /var/log/z-push \
    && chown -R vmail:vmail /usr/share/z-push /data/zpush-state /var/log/z-push

# --- goimapnotify binary from build stage ------------------------------------
COPY --from=gobuild /out/goimapnotify /usr/local/bin/

RUN mkdir -p /data/maildir && chown -R vmail:vmail /data/maildir

# --- static config -----------------------------------------------------------
COPY config/zpush/config.php        /usr/share/z-push/config.php
COPY config/zpush/imap.php          /usr/share/z-push/backend/imap/config.php
COPY config/nginx/zpush.conf        /etc/nginx/sites-enabled/default
COPY config/dovecot/dovecot.conf    /etc/dovecot/dovecot.conf
COPY config/dovecot/conf.d/         /etc/dovecot/conf.d/
COPY config/dovecot/templates/      /etc/dovecot/templates/
COPY config/mbsync/mbsyncrc.template        /etc/mbsync/mbsyncrc.template
COPY config/imapnotify/gmail.json.template  /etc/imapnotify/gmail.json.template
COPY supervisord.conf /etc/supervisor/conf.d/stack.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh \
    && chown vmail:vmail /usr/share/z-push/config.php /usr/share/z-push/backend/imap/config.php

EXPOSE 80
VOLUME ["/data"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

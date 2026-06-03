# h-yt-dlp — sync YouTube playlists → biblioteca Navidrome.
#
# Cron runtime: supercronic (Aptible) — substitui busybox crond.
# Razão: busybox crond exige `CAP_SETUID`/`CAP_SETGID` (root) e lê
# `/etc/crontabs/root` com mode 600 root:root → incompatível com
# `user: 1000:1000 + cap_drop: ALL`. Supercronic corre como qualquer
# user, foreground, captura stdout dos jobs (sem ficheiros de log).
# Source: https://github.com/aptible/supercronic

FROM python:3.14-alpine

ARG YT_DLP_VERSION=2026.03.17
ARG SUPERCRONIC_VERSION=0.2.46
ARG TARGETARCH=amd64

RUN apk add --no-cache ffmpeg ca-certificates tzdata curl \
 && pip install --no-cache-dir yt-dlp==${YT_DLP_VERSION} \
 && yt-dlp --version \
 && curl -fsSL -o /usr/local/bin/supercronic \
    "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-${TARGETARCH}" \
 && chmod +x /usr/local/bin/supercronic \
 && apk del curl

COPY scripts/sync.sh /usr/local/bin/sync.sh
COPY scripts/crontab /etc/crontab
RUN chmod +x /usr/local/bin/sync.sh

USER 1000:1000
ENTRYPOINT ["supercronic", "/etc/crontab"]

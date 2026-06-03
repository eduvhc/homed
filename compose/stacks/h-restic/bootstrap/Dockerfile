# h-restic — engine de backup (single-container, supercronic-driven).
# Pattern alinhado com h-yt-dlp e forgejo-bootstrap (custom image, multiplex).
#
# Layers:
#   restic 0.18.1 (binário copiado da image scratch oficial)
#   alpine + supercronic 0.2.46 (cron foreground, non-root, structured logs)
#   curl (POST deadman aos endpoints externos do gatus)

FROM restic/restic:0.18.1 AS restic-bin

FROM alpine:3.20

ARG SUPERCRONIC_VERSION=0.2.46
ARG TARGETARCH=amd64

RUN apk add --no-cache curl ca-certificates tzdata \
 && curl -fsSL -o /usr/local/bin/supercronic \
    "https://github.com/aptible/supercronic/releases/download/v${SUPERCRONIC_VERSION}/supercronic-linux-${TARGETARCH}" \
 && chmod +x /usr/local/bin/supercronic

COPY --from=restic-bin /usr/bin/restic /usr/local/bin/restic
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY crontab /etc/crontab

USER 1000:1000
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

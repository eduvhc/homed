FROM python:3.12-alpine

# yt-dlp precisa de ffmpeg para extrair áudio + embed thumb
RUN apk add --no-cache ffmpeg ca-certificates tzdata \
 && pip install --no-cache-dir --upgrade yt-dlp \
 && yt-dlp --version

# scripts e crontab
COPY scripts/sync.sh   /usr/local/bin/sync.sh
COPY scripts/crontab   /etc/crontabs/root
RUN chmod +x /usr/local/bin/sync.sh

# Foreground crond; logs vão para stdout via -L /dev/stdout
ENTRYPOINT ["sh", "-c", "echo '[h-yt-dlp] cron a iniciar — próxima execução conforme /etc/crontabs/root'; crond -f -L /dev/stdout -l 2"]

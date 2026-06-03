#!/bin/sh
# Sync de playlists/canais YouTube para a biblioteca Navidrome.
# - Lê URLs (uma por linha) de /config/playlists.txt
# - Usa opções globais de /config/yt-dlp.conf
# - Escreve em /music/<Canal>/<Playlist>/<Título>.<ext>
# - /config/archive.txt previne re-download

set -eu

PLAYLISTS=/config/playlists.txt
ARCHIVE=/config/archive.txt
MUSIC=/music

[ -f "$PLAYLISTS" ] || { echo "$(date -Iseconds) ERRO: $PLAYLISTS não existe"; exit 1; }
mkdir -p "$MUSIC"
touch "$ARCHIVE"

echo "$(date -Iseconds) [h-yt-dlp] start"

# Lê linha-a-linha, ignora vazias e comentários (#)
grep -vE '^[[:space:]]*(#|$)' "$PLAYLISTS" | while IFS= read -r url; do
  echo "$(date -Iseconds) → $url"
  yt-dlp \
    --config-location /config/yt-dlp.conf \
    --download-archive "$ARCHIVE" \
    --paths "$MUSIC" \
    "$url" \
    || echo "$(date -Iseconds) WARN: falhou — '$url' (continuando)"
done

echo "$(date -Iseconds) [h-yt-dlp] done"

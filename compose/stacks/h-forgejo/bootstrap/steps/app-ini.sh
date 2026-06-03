#!/bin/sh
# app-ini step — seed /var/lib/gitea/custom/conf/app.ini do mount git-tracked.
# Idempotente via hash sentinel: re-copia só se source mudou.
#
# Source-verified:
#   Dockerfile.rootless:106 — GITEA_APP_INI=/var/lib/gitea/custom/conf/app.ini
#   docker-setup.sh:15 — só renderiza template se file não existe
#   docker-setup.sh:51 — env-to-ini SEMPRE corre contra $GITEA_APP_INI
# Sem este step, docker-setup gera template default (sqlite3, INSTALL_LOCK=false)
# e ignora totalmente o ./config/app.ini montado em /etc/gitea/ (path errado).
set -eu

SRC=/etc/gitea/app.ini.source           # bind mount :ro do git-tracked
DST=/var/lib/gitea/custom/conf/app.ini  # path canónico do upstream
SENTINEL=/var/lib/gitea/custom/conf/.app.ini.sha256

[ -f "$SRC" ] || { echo "ERR: $SRC não montado (verifica volumes)"; exit 1; }

mkdir -p "$(dirname "$DST")"

SRC_HASH=$(sha256sum "$SRC" | awk '{print $1}')
CUR_HASH=""
[ -f "$SENTINEL" ] && CUR_HASH=$(cat "$SENTINEL")

if [ "$SRC_HASH" = "$CUR_HASH" ] && [ -f "$DST" ]; then
  echo "skip: app.ini já seeded (hash match: $SRC_HASH)"
else
  cp "$SRC" "$DST"
  printf '%s' "$SRC_HASH" > "$SENTINEL"
  echo "✓ app.ini seeded em $DST (hash: $SRC_HASH)"
fi

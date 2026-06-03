#!/bin/sh
# forgejo-bootstrap dispatcher — escolhe step por $BOOTSTRAP_STEP.
#
# Adopta o pattern do upstream docker-setup.sh: copia o app.ini :ro para
# /tmp (writable) + corre environment-to-ini para fundir env vars FORGEJO__*
# no ini. Sem isto, Forgejo CLI tenta auto-gerar INTERNAL_TOKEN + escrever
# em /etc/gitea/app.ini (read-only mount) → falha.
# Source: docker-setup.sh upstream linha final "environment-to-ini --config $GITEA_APP_INI"
set -eu

: "${BOOTSTRAP_STEP:?BOOTSTRAP_STEP required (admin|oidc|config)}"

# Prepare writable app.ini (ephemeral per container; env-to-ini injecta os
# overrides FORGEJO__section__KEY). Steps usam --config $APP_INI.
export APP_INI=/tmp/app.ini
cp /etc/gitea/app.ini "$APP_INI"
chmod 600 "$APP_INI"
environment-to-ini --config "$APP_INI"

STEP="/usr/local/bin/steps/${BOOTSTRAP_STEP}.sh"
[ -x "$STEP" ] || { echo "ERR: step '$BOOTSTRAP_STEP' não existe"; exit 1; }

exec "$STEP"

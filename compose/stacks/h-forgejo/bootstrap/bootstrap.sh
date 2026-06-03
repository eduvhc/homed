#!/bin/sh
# forgejo-bootstrap dispatcher — escolhe step por $BOOTSTRAP_STEP.
# Steps: app-ini (seed /var/lib/gitea/custom/conf/app.ini do mount git-tracked),
#        admin (cria admin CLI), oidc (registra auth source CLI),
#        config (REST: repo + PAT + webhook).
set -eu

: "${BOOTSTRAP_STEP:?BOOTSTRAP_STEP required (app-ini|admin|oidc|config)}"

STEP="/usr/local/bin/steps/${BOOTSTRAP_STEP}.sh"
[ -x "$STEP" ] || { echo "ERR: step '$BOOTSTRAP_STEP' não existe"; exit 1; }

exec "$STEP"

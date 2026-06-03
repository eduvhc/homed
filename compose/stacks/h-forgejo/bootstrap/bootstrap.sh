#!/bin/sh
# forgejo-bootstrap dispatcher — escolhe step por $BOOTSTRAP_STEP.
set -eu

: "${BOOTSTRAP_STEP:?BOOTSTRAP_STEP required (admin|oidc|config)}"

STEP="/usr/local/bin/steps/${BOOTSTRAP_STEP}.sh"
[ -x "$STEP" ] || { echo "ERR: step '$BOOTSTRAP_STEP' não existe"; exit 1; }

exec "$STEP"

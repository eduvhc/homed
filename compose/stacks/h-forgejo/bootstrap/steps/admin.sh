#!/bin/sh
# admin step — cria 1º admin via forgejo CLI (idempotente).
# Source: forgejo cmd/admin_user_create.go — `--admin --must-change-password=false`.
set -eu

: "${FORGEJO_ADMIN_USERNAME:?}"
: "${FORGEJO_ADMIN_PASSWORD:?}"
: "${FORGEJO_ADMIN_EMAIL:?}"

if forgejo admin user list 2>/dev/null | awk 'NR>1 {print $2}' | grep -qx "$FORGEJO_ADMIN_USERNAME"; then
  echo "skip: admin '$FORGEJO_ADMIN_USERNAME' já existe"
else
  forgejo admin user create \
    --username "$FORGEJO_ADMIN_USERNAME" \
    --password "$FORGEJO_ADMIN_PASSWORD" \
    --email    "$FORGEJO_ADMIN_EMAIL" \
    --admin --must-change-password=false
  echo "✓ admin '$FORGEJO_ADMIN_USERNAME' criado"
fi

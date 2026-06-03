#!/bin/sh
# admin step — cria/renomeia 1º admin via forgejo CLI (idempotente).
# Source:
#   cmd/main.go:67           (--config global flag)
#   cmd/admin_user_create.go (--admin --must-change-password)
#   cmd/admin_user_change_username.go (--username --new-username)
# CONFIG path: canónico do upstream (Dockerfile.rootless:106), partilhado com
# o runtime via volume h-forgejo-data — mesmo file, mesma DB.
set -eu

: "${FORGEJO_ADMIN_USERNAME:?}"
: "${FORGEJO_ADMIN_PASSWORD:?}"
: "${FORGEJO_ADMIN_EMAIL:?}"

CONFIG=/var/lib/gitea/custom/conf/app.ini
HAS_USER() { forgejo --config "$CONFIG" admin user list 2>/dev/null | awk 'NR>1 {print $2}' | grep -qx "$1"; }

# Migração declarativa idempotente: se FORGEJO_ADMIN_PREVIOUS_USERNAME existe
# e o actual ainda não, renomeia. Pós-rename, OLD não existe → noop em runs futuras.
OLD="${FORGEJO_ADMIN_PREVIOUS_USERNAME:-}"
if [ -n "$OLD" ] && [ "$OLD" != "$FORGEJO_ADMIN_USERNAME" ] \
   && HAS_USER "$OLD" && ! HAS_USER "$FORGEJO_ADMIN_USERNAME"; then
  forgejo --config "$CONFIG" admin user change-username \
    --username "$OLD" --new-username "$FORGEJO_ADMIN_USERNAME"
  echo "✓ admin renomeado: $OLD → $FORGEJO_ADMIN_USERNAME"
fi

# Create se ainda não existe (idempotente).
if HAS_USER "$FORGEJO_ADMIN_USERNAME"; then
  echo "skip: admin '$FORGEJO_ADMIN_USERNAME' já existe"
else
  forgejo --config "$CONFIG" admin user create \
    --username "$FORGEJO_ADMIN_USERNAME" \
    --password "$FORGEJO_ADMIN_PASSWORD" \
    --email    "$FORGEJO_ADMIN_EMAIL" \
    --admin --must-change-password=false
  echo "✓ admin '$FORGEJO_ADMIN_USERNAME' criado"
fi

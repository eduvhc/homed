#!/bin/sh
# admin step — cria 1º admin via forgejo CLI (idempotente).
# Source:
#   cmd/main.go:67          (--config global flag)
#   cmd/admin_user_create.go (--admin --must-change-password flags)
# Why --config: a image base codeberg.org/forgejo/forgejo:15-rootless tem
# o seu próprio docker-entrypoint que setup env vars (GITEA_WORK_DIR etc).
# Como substituímos o ENTRYPOINT para o dispatcher, precisamos de passar
# --config explicitamente para forgejo encontrar app.ini.
set -eu

: "${FORGEJO_ADMIN_USERNAME:?}"
: "${FORGEJO_ADMIN_PASSWORD:?}"
: "${FORGEJO_ADMIN_EMAIL:?}"

CONFIG=/etc/gitea/app.ini

if forgejo --config "$CONFIG" admin user list 2>/dev/null | awk 'NR>1 {print $2}' | grep -qx "$FORGEJO_ADMIN_USERNAME"; then
  echo "skip: admin '$FORGEJO_ADMIN_USERNAME' já existe"
else
  forgejo --config "$CONFIG" admin user create \
    --username "$FORGEJO_ADMIN_USERNAME" \
    --password "$FORGEJO_ADMIN_PASSWORD" \
    --email    "$FORGEJO_ADMIN_EMAIL" \
    --admin --must-change-password=false
  echo "✓ admin '$FORGEJO_ADMIN_USERNAME' criado"
fi

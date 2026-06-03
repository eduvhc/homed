#!/bin/sh
# oidc step — regista Authelia como OAuth2 OIDC auth source (idempotente).
# Source:
#   cmd/main.go:67           (--config global flag)
#   cmd/admin_auth_oauth.go:217 (addOauth cria auth_model.Source)
# `[oauth2_client]` em app.ini só ajusta comportamento — não cria providers,
# tem que ser CLI para o botão "Sign in with Authelia" aparecer no login.
# --config: ver nota em admin.sh sobre custom ENTRYPOINT.
set -eu

: "${OIDC_SOURCE_NAME:?}"
: "${OIDC_CLIENT_ID:?}"
: "${OIDC_FORGEJO_CLIENT_SECRET:?}"
: "${OIDC_DISCOVERY_URL:?}"

CONFIG="${APP_INI:-/etc/gitea/app.ini}"

if forgejo --config "$CONFIG" admin auth list 2>/dev/null | awk 'NR>1 {print $2}' | grep -qx "$OIDC_SOURCE_NAME"; then
  echo "skip: OIDC source '$OIDC_SOURCE_NAME' já existe"
else
  forgejo --config "$CONFIG" admin auth add-oauth \
    --name "$OIDC_SOURCE_NAME" \
    --provider openidConnect \
    --key "$OIDC_CLIENT_ID" \
    --secret "$OIDC_FORGEJO_CLIENT_SECRET" \
    --auto-discover-url "$OIDC_DISCOVERY_URL" \
    --scopes openid --scopes email --scopes profile --scopes groups \
    --group-claim-name groups
  echo "✓ OIDC source '$OIDC_SOURCE_NAME' registado"
fi

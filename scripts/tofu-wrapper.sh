#!/bin/sh
# tofu-wrapper.sh — cross-OS tofu wrapper. Lê CLOUDFLARE_API_TOKEN e
# HOMED_TOFU_ENCRYPTION via Bitwarden Secrets Manager (bws CLI) e
# executa `tofu <CMD>` dentro de tofu/.
#
# Pré-req no operador (uma vez por máquina): bws instalado + env vars
# BWS_ACCESS_TOKEN e HOMED_BWS_PROJECT_ID exportadas.
#
# Uso: scripts/tofu-wrapper.sh <tofu-args...>
#   e.g.: scripts/tofu-wrapper.sh plan
#         scripts/tofu-wrapper.sh output -raw tunnel_token
set -eu

command -v bws >/dev/null 2>&1 \
  || { echo "bws CLI não instalado. https://bitwarden.com/help/secrets-manager-cli/" >&2; exit 1; }
command -v jq  >/dev/null 2>&1 \
  || { echo "jq não instalado. (apt install jq | brew install jq | winget install stedolan.jq)" >&2; exit 1; }
: "${BWS_ACCESS_TOKEN:?export BWS_ACCESS_TOKEN=<machine-account-token>}"
: "${HOMED_BWS_PROJECT_ID:?export HOMED_BWS_PROJECT_ID=<project-uuid>}"

# bws run injecta os secrets do projecto como env vars no sub-shell.
# Passamos os args ($*) via TOFU_ARGS para sobreviverem ao sub-shell quoting.
# shellcheck disable=SC2016  # single quotes intencional: $VARs expandem só dentro do bws sub-shell, depois de injecção.
TOFU_ARGS="$*" \
bws run --project-id "$HOMED_BWS_PROJECT_ID" -- '
  set -eu
  : "${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN não está no projecto bws}"
  : "${HOMED_TOFU_ENCRYPTION:?HOMED_TOFU_ENCRYPTION não está no projecto bws}"
  export TF_VAR_cf_api_token="$CLOUDFLARE_API_TOKEN"
  TF_VAR_cf_account_id=$(curl -sfH "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    https://api.cloudflare.com/client/v4/accounts | jq -r ".result[0].id")
  TF_VAR_cf_zone_id=$(curl -sfH "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    "https://api.cloudflare.com/client/v4/zones?name=iedora.com" | jq -r ".result[0].id")
  export TF_VAR_cf_account_id TF_VAR_cf_zone_id
  export TF_VAR_encryption_passphrase="$HOMED_TOFU_ENCRYPTION"
  cd tofu && eval "tofu $TOFU_ARGS"
'

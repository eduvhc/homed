#!/bin/sh
# bootstrap-age-key.sh — operator-side, idempotente, cross-OS.
# Fetch da age private key (HOMED_AGE_KEY) de Bitwarden Secrets Manager para
# ~/.config/sops/age/keys.txt. Corre uma vez por máquina nova; daí em diante
# salta silenciosamente.
#
# Pré-req: bws CLI + BWS_ACCESS_TOKEN + HOMED_BWS_PROJECT_ID exportados.
# Secret esperado no projecto: key="HOMED_AGE_KEY", value=conteúdo do
# ficheiro age (multi-line, inclui linhas '# created:' + AGE-SECRET-KEY-1…).
#
# Server-side (Beelink): NUNCA corre isto. A age key chega via
# ansible.builtin.copy a partir do operator (provision.yml).
set -eu

DEST="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

if [ -f "$DEST" ]; then
  echo "skip: age key já existe em $DEST"
  exit 0
fi

command -v bws >/dev/null 2>&1 \
  || { echo "✗ bws CLI não instalado. https://bitwarden.com/help/secrets-manager-cli/" >&2; exit 1; }
: "${BWS_ACCESS_TOKEN:?export BWS_ACCESS_TOKEN=<machine-account-token>}"
: "${HOMED_BWS_PROJECT_ID:?export HOMED_BWS_PROJECT_ID=<project-uuid>}"

mkdir -p "$(dirname "$DEST")"
chmod 700 "$(dirname "$DEST")"

# bws run injecta cada secret do projecto como env var nomeada por `key`.
# Pattern igual ao scripts/tofu-wrapper.sh — single quotes intencional para
# $HOMED_AGE_KEY expandir só dentro do sub-shell injectado pelo bws.
# shellcheck disable=SC2016
bws run --project-id "$HOMED_BWS_PROJECT_ID" -- sh -c '
  : "${HOMED_AGE_KEY:?HOMED_AGE_KEY não está no projecto bws}"
  printf "%s\n" "$HOMED_AGE_KEY"
' > "$DEST"
chmod 600 "$DEST"

echo "✓ age key fetched de bws → $DEST (mode 600)"

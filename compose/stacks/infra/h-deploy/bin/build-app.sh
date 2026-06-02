#!/bin/bash
# build-app.sh — push à main de uma app monorepo.
#
# Args (vêm dos hooks.yaml pass-arguments-to-command):
#   $1 = APP (nome do repo / serviço — ex.: "lyzer-monorepo")
#   $2 = SHA (commit completo do payload "after")
#
# Convenção: o nome do repo na URL é igual ao nome do serviço no compose.
# Se precisares de mapear, edita REPO_TO_SERVICE abaixo.

set -euo pipefail

LOG=/var/log/deploy/app.log
mkdir -p "$(dirname "$LOG")"

log() { echo "$(date -Iseconds) [$APP] $*" | tee -a "$LOG" ; }

APP="${1:?app name required}"
SHA="${2:?commit sha required}"
SHORT_SHA="${SHA:0:7}"

# Mapping repo → service name (extender quando necessário)
case "$APP" in
  lyzer-monorepo) SERVICE="lyzer-web-app" ;;
  *)              SERVICE="${APP}-app" ;;
esac

REPO_URL="git@github.com:lyzer/${APP}.git"
WORKDIR="/workspace/${APP}"
HOMED=/homed
IMAGE="lyzer/${APP}"

trap 'log "FAIL: $BASH_COMMAND (exit $?)"; report_failure; exit 1' ERR

report_failure() {
  if [[ -n "${GATUS_TOKEN:-}" ]]; then
    curl -fsS -m 5 -X POST \
      "http://h-gatus:8080/api/v1/endpoints/ops_deploy-${APP}/external?token=${GATUS_TOKEN}&success=false" \
      > /dev/null 2>&1 || true
  fi
}

log "─── build-app start @ ${SHORT_SHA} (event=${GIT_EVENT:-?}) ───"

# 1. Sync repo
if [[ ! -d "$WORKDIR/.git" ]]; then
  log "clone inicial → $WORKDIR"
  git clone --depth=50 "$REPO_URL" "$WORKDIR"
else
  log "fetch + reset"
  git -C "$WORKDIR" fetch origin main
  git -C "$WORKDIR" reset --hard "$SHA"
fi

ACTUAL_SHA=$(git -C "$WORKDIR" rev-parse HEAD)
if [[ "$ACTUAL_SHA" != "$SHA" ]]; then
  log "AVISO: SHA divergente — payload=$SHA, repo=$ACTUAL_SHA"
fi

# 2. Build com dupla tag (:latest + :sha-XXXX)
log "docker build → ${IMAGE}:latest, ${IMAGE}:sha-${SHORT_SHA}"
docker build \
  --tag "${IMAGE}:latest" \
  --tag "${IMAGE}:sha-${SHORT_SHA}" \
  --label "homed.deploy.sha=${SHA}" \
  --label "homed.deploy.at=$(date -Iseconds)" \
  "$WORKDIR"

# 3. Restart só do service afectado (compose recalcula deps automaticamente)
log "docker compose up -d --no-deps ${SERVICE}"
docker compose -f "$HOMED/compose/compose.yaml" up -d --no-deps "$SERVICE"

# 4. Prune: mantém as 5 últimas SHAs por imagem, apaga as outras
log "prune (keep last 5 SHA tags)"
docker images "${IMAGE}" --format '{{.Tag}}\t{{.CreatedAt}}' \
  | grep -E '^sha-' \
  | sort -k2 -r \
  | awk 'NR>5 {print $1}' \
  | xargs -r -I{} docker rmi "${IMAGE}:{}" 2>/dev/null || true

# 5. Heartbeat OK
if [[ -n "${GATUS_TOKEN:-}" ]]; then
  curl -fsS -m 5 -X POST \
    "http://h-gatus:8080/api/v1/endpoints/ops_deploy-${APP}/external?token=${GATUS_TOKEN}&success=true" \
    > /dev/null 2>&1 || log "gatus heartbeat failed (non-fatal)"
fi

log "─── build-app OK @ ${SHORT_SHA} ───"

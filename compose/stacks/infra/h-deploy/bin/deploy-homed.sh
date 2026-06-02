#!/bin/bash
# deploy-homed.sh — push ao repo iedora/homed.
# Faz pull do mirror local, decrypta secrets, puxa imagens e refaz a DAG.
#
# Como funciona o "self-update":
#   /homed (read-only mount) é onde os ficheiros do compose já vivem.
#   Não conseguimos fazer git pull dentro do container nem editar /homed.
#   Em vez disso: clonamos/pull num workspace, depois aplicamos via SSH
#   ao próprio host (que tem a sua working tree).
#
# Para já: este script faz APENAS pull num espelho em /workspace/homed
# e dispara o `task up` no homed local. O git pull "real" do working tree
# do host fica para implementação posterior (precisa de SSH ao host ou de
# sair do read-only mount).

set -euo pipefail

LOG=/var/log/deploy/homed.log
mkdir -p "$(dirname "$LOG")"

log() { echo "$(date -Iseconds) $*" | tee -a "$LOG" ; }

REPO_URL="${HOMED_REPO_URL:-git@github.com:eduvhc/homed.git}"
MIRROR=/workspace/homed
HOMED=/homed   # mount read-only do working tree no host

trap 'log "FAIL: $BASH_COMMAND (exit $?)"; exit 1' ERR

log "─── deploy-homed start (event=${GIT_EVENT:-?}) ───"

# 1. Mirror local actualizado (para auditoria + diff).
if [[ ! -d "$MIRROR/.git" ]]; then
  log "clone inicial → $MIRROR"
  git clone --depth=50 "$REPO_URL" "$MIRROR"
else
  log "pull → $MIRROR"
  git -C "$MIRROR" fetch origin main
  git -C "$MIRROR" reset --hard origin/main
fi

NEW_SHA=$(git -C "$MIRROR" rev-parse --short HEAD)
log "homed @ ${NEW_SHA}"

# 2. Detectar se tofu/ mudou desde o último deploy → trigger separado.
LAST_SHA_FILE=/var/log/deploy/homed-last-sha
if [[ -f "$LAST_SHA_FILE" ]]; then
  LAST_SHA=$(cat "$LAST_SHA_FILE")
  if git -C "$MIRROR" diff --quiet "$LAST_SHA" HEAD -- tofu/; then
    log "tofu/ unchanged since $LAST_SHA"
  else
    log "tofu/ changed — manual 'task tofu-apply' required (skipping)"
    # Em prod: enviar alerta via Gatus push para o utilizador fazer apply manual.
  fi
fi

# 3. Pull imagens com tags pinadas que mudaram.
log "docker compose pull"
docker compose -f "$HOMED/compose/compose.yaml" pull --quiet

# 4. Recriar containers cujo config/image mudou.
log "docker compose up -d --remove-orphans"
docker compose -f "$HOMED/compose/compose.yaml" up -d --remove-orphans

# 5. Guardar SHA aplicada para próximo diff.
echo "$NEW_SHA" > "$LAST_SHA_FILE"

# 6. Heartbeat push para Gatus (deadman switch).
if [[ -n "${GATUS_TOKEN:-}" ]]; then
  curl -fsS -m 5 -X POST \
    "http://h-gatus:8080/api/v1/endpoints/ops_deploy-homed/external?token=${GATUS_TOKEN}&success=true" \
    > /dev/null 2>&1 || log "gatus heartbeat failed (non-fatal)"
fi

log "─── deploy-homed OK @ ${NEW_SHA} ───"

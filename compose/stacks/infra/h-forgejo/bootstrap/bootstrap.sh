#!/bin/sh
# forgejo-config-bootstrap — provisiona PAT + webhook do repo no Forgejo,
# escreve as credenciais em /shared para o h-doco-cd consumir.
#
# Idempotente: GET antes de POST, recria PAT se volume foi limpo (deleta o
# token velho com mesmo nome no Forgejo antes), webhook actualizado via PATCH
# se já existir.

set -eu

: "${FORGEJO_URL:?FORGEJO_URL obrigatório (ex.: http://h-forgejo:3000)}"
: "${FORGEJO_ADMIN_USERNAME:?}"
: "${FORGEJO_ADMIN_PASSWORD:?}"
: "${REPO_OWNER:?REPO_OWNER obrigatório}"
: "${REPO_NAME:?REPO_NAME obrigatório}"
: "${WEBHOOK_URL:?WEBHOOK_URL obrigatório}"
: "${TOKEN_NAME:=h-doco-cd}"
: "${WEBHOOK_BRANCH:=main}"
: "${UPSTREAM_REPO:?UPSTREAM_REPO obrigatório (ex.: https://github.com/eduvhc/homed.git)}"

SHARED=/shared
mkdir -p "$SHARED"
chmod 700 "$SHARED"

auth() { printf '%s' "-u${FORGEJO_ADMIN_USERNAME}:${FORGEJO_ADMIN_PASSWORD}"; }
api()  { curl -fsS $(auth) -H 'Content-Type: application/json' "$@"; }

# 0. Espera pelo Forgejo healthy (depends_on já o faz, mas double-check no caso
# de healthcheck ser optimista).
echo "→ wait Forgejo @ $FORGEJO_URL"
i=0
until curl -fsS "$FORGEJO_URL/api/healthz" >/dev/null 2>&1; do
  i=$((i+1)); [ "$i" -ge 60 ] && { echo "Forgejo não responde"; exit 1; }
  sleep 1
done

# 1. Garante que o repo existe — importa do upstream público se ainda não.
# Idempotente: 200 = repo existe (skip), caso contrário POST /repos/migrate.
if api -o /dev/null -w '%{http_code}' "$FORGEJO_URL/api/v1/repos/$REPO_OWNER/$REPO_NAME" 2>/dev/null | grep -q '^200$'; then
  echo "skip: repo $REPO_OWNER/$REPO_NAME já existe"
else
  echo "→ importing $UPSTREAM_REPO → $REPO_OWNER/$REPO_NAME"
  api -X POST "$FORGEJO_URL/api/v1/repos/migrate" \
    -d "$(jq -nc \
      --arg url "$UPSTREAM_REPO" \
      --arg owner "$REPO_OWNER" \
      --arg name "$REPO_NAME" \
      '{clone_addr:$url, repo_owner:$owner, repo_name:$name, mirror:false, private:false, description:"homelab declarativo · imported from upstream"}')" \
    >/dev/null
  echo "✓ repo importado de $UPSTREAM_REPO"
fi

# 2. PAT — sempre regenera se o volume não tem (handle volume reset gracefully)
TOKEN_FILE="$SHARED/git_access_token"
if [ ! -s "$TOKEN_FILE" ]; then
  # Apaga token velho com mesmo nome no Forgejo (volume foi reset)
  api -o /dev/null -w '' -X DELETE \
    "$FORGEJO_URL/api/v1/users/$FORGEJO_ADMIN_USERNAME/tokens/$TOKEN_NAME" 2>/dev/null || true

  TOKEN=$(api -X POST "$FORGEJO_URL/api/v1/users/$FORGEJO_ADMIN_USERNAME/tokens" \
    -d "$(jq -nc --arg n "$TOKEN_NAME" '{name:$n, scopes:["read:repository"]}')" \
    | jq -r '.sha1')
  [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ] || { echo "✗ falha a criar PAT"; exit 1; }
  printf '%s' "$TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
  echo "✓ PAT criado: $TOKEN_NAME"
else
  echo "skip: PAT já existe em $TOKEN_FILE"
fi

# 3. Webhook secret — gerado uma vez por volume
SECRET_FILE="$SHARED/webhook_secret"
if [ ! -s "$SECRET_FILE" ]; then
  head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n' > "$SECRET_FILE"
  chmod 600 "$SECRET_FILE"
  echo "✓ webhook secret gerado"
fi
SECRET=$(cat "$SECRET_FILE")

# 4. Webhook upsert — POST se não existe, PATCH se sim
HOOK_PAYLOAD=$(jq -nc \
  --arg url "$WEBHOOK_URL" \
  --arg branch "$WEBHOOK_BRANCH" \
  --arg secret "$SECRET" \
  '{type:"forgejo", branch_filter:$branch, events:["push"], active:true,
    config:{url:$url, content_type:"json", secret:$secret}}')

HOOK_ID=$(api "$FORGEJO_URL/api/v1/repos/$REPO_OWNER/$REPO_NAME/hooks" \
  | jq -r --arg url "$WEBHOOK_URL" '.[] | select(.config.url == $url) | .id' | head -1)

if [ -z "$HOOK_ID" ]; then
  api -X POST "$FORGEJO_URL/api/v1/repos/$REPO_OWNER/$REPO_NAME/hooks" \
    -d "$HOOK_PAYLOAD" >/dev/null
  echo "✓ webhook criado → $WEBHOOK_URL"
else
  api -X PATCH "$FORGEJO_URL/api/v1/repos/$REPO_OWNER/$REPO_NAME/hooks/$HOOK_ID" \
    -d "$HOOK_PAYLOAD" >/dev/null
  echo "✓ webhook actualizado (id=$HOOK_ID)"
fi

echo "ready: $REPO_OWNER/$REPO_NAME → $WEBHOOK_URL"

# tofu/

OpenTofu para tudo o que é Cloudflare/R2 do homed.

## Layout

Prefixo `_` agrupa ficheiros de **setup/meta** (providers, encryption, vars, outputs)
no topo do `ls`. Ficheiros de **recursos cloud** ficam por baixo, um por concern.

```
tofu/
├── _providers.tf            # providers + version pinning
├── _encryption.tf           # client-side state encryption (AES-GCM, pré-upload)
├── _backend.tf              # remote state em R2 (lockfile nativo via conditional writes)
├── _variables.tf            # inputs (CF creds, IDs, defaults)
├── _outputs.tf              # outputs (sensitive: tunnel_token, r2_endpoint)
├── dns.tf                   # CNAME records *.iedora.com → tunnel
├── tunnel.tf                # Zero Trust Tunnel + token data source
├── r2.tf                    # bucket + lifecycle (180d fallback expiry)
└── README.md                # este ficheiro
```

Sem módulos. 3 resources cloud não justificam o overhead — ficaria 9 ficheiros para o que cabe em 3.

## O que está aqui automatizado

- DNS records `*.iedora.com` → tunnel (proxied)
- Cloudflare Zero Trust Tunnel `homed` (com secret gerado por `random`)
- R2 bucket `homed-backups` + lifecycle (180d expiry como fallback)
- State encryption nativo Tofu 1.10+ (AES-GCM com passphrase via PBKDF2)

## O que é manual (uma vez)

Cloudflare R2 S3-compatible credentials para o Restic **não são criáveis** pelo provider atual.
Cria no dashboard:

1. Cloudflare Dashboard → R2 Object Storage → **Manage R2 API Tokens** → Create token
2. Permissions: `Object Read & Write`, bucket `homed-backups`
3. TTL: sem expiração (rotação manual de 6 em 6 meses)
4. Guarda **Access Key ID** + **Secret Access Key** em `secrets/h-restic.env` (encriptado in-place):
   ```bash
   cat > secrets/h-restic.env <<EOF
   AWS_ACCESS_KEY_ID=<...>
   AWS_SECRET_ACCESS_KEY=<...>
   RESTIC_PASSWORD=<gerar com: openssl rand -hex 32>
   RESTIC_REPOSITORY=<output tofu r2_endpoint>
   HC_PING_URL=https://hc-ping.com/<uuid de healthchecks.io>
   EOF
   task secrets:lock
   ```

## Setup inicial (macOS / Linux / Windows — cross-OS)

Zero ficheiros de credenciais. Tudo vem do **Bitwarden Secrets Manager** + **CF API**:

```bash
# 1. Instalar bws CLI (uma vez, qualquer OS)
#    https://github.com/bitwarden/sdk-sm/releases  (bws-v2.1.0+)
#    Extrair o binário 'bws' para algures no PATH.

# 2. Criar secrets no projecto Bitwarden Secrets Manager:
#    - CLOUDFLARE_API_TOKEN   (gerado em CF dashboard, ver permissões abaixo)
#    - HOMED_TOFU_ENCRYPTION  (passphrase aleatória 32+ bytes — gera com `openssl rand -hex 32`)

# Que permissões o CF token precisa:
#   - Account → R2 Storage → Edit
#   - Zone → DNS → Edit
#   - Account → Cloudflare Tunnel → Edit
#   - User → User Details → Read

# 3. Exportar credenciais bws no shell (qualquer OS):
export BWS_ACCESS_TOKEN=<machine-account-token>
export HOMED_BWS_PROJECT_ID=<project-uuid>

# 4. Operação
task tofu CMD=init            # primeira vez (descarrega providers)
task tofu CMD=plan            # mostra mudanças propostas
task tofu CMD=apply           # aplica
task tofu:sync-secrets        # exporta tunnel_token para secrets/h-cloudflared.env (encriptado in-place)
```

**O que está no projecto bws** (operador, qualquer OS):
- `CLOUDFLARE_API_TOKEN` — adicionado por ti
- `HOMED_TOFU_ENCRYPTION` — passphrase para state encryption (gerar com `openssl rand -hex 32`)
- `HOMED_AGE_KEY` — chave privada age usada por sops (ver `.taskfiles/secrets.yaml`)
- `R2_STATE_ACCESS_KEY` + `R2_STATE_SECRET_KEY` — R2 API tokens com Object Read & Write em `homed-backups` (para backend remoto do state; ver migration steps abaixo)

**O que vem da CF API em runtime (não persistido):**
- `cf_account_id` (descoberto de `/accounts`)
- `cf_zone_id` (descoberto de `/zones?name=iedora.com`)

Beelink não corre `tofu` nem precisa de bws — apply roda no operador, e o
`tunnel_token` chega ao servidor via `secrets/h-cloudflared.env` (encriptado
in-place por `task tofu:sync-secrets`).

## Remote state em R2 (migration one-time)

State vive em `homed-backups` bucket, prefix `tofu/homed.tfstate`. Encriptado
client-side (AES-GCM via `_encryption.tf`) **antes** do upload — R2 vê só
ciphertext. Lock nativo via S3 conditional writes (OpenTofu 1.10+,
`use_lockfile = true` em `_backend.tf`). Sem DynamoDB.

**Migration steps** (correr 1× quando o backend mudar de local para R2):

```bash
# 1. Criar R2 API tokens dedicados ao state em CF dashboard:
#    R2 → Manage R2 API Tokens → Create → Permissions: Object Read & Write
#    Bucket: homed-backups
#    Guardar Access Key ID + Secret Access Key.

# 2. Adicionar ao projecto bws:
bws secret create R2_STATE_ACCESS_KEY <access-key-id> "$HOMED_BWS_PROJECT_ID"
bws secret create R2_STATE_SECRET_KEY <secret-access-key> "$HOMED_BWS_PROJECT_ID"

# 3. Migrar state local → R2:
task tofu CMD=init           # detecta novo backend, oferece migrate-state — yes
#   (wrapper passa -reconfigure + endpoints dinâmico via bws account_id)

# 4. Confirmar:
task tofu CMD='state list' | head -3    # lista resources como antes — agora vindo de R2
```

**Cold-start (laptop novo)**: bws + mise instalados (ver README raiz),
clone do repo, exportar `BWS_ACCESS_TOKEN`+`HOMED_BWS_PROJECT_ID`. `task tofu CMD=init`
reconstitui `.terraform/` local a partir do state R2. Zero ficheiros locais
pré-existentes — laptop é descartável.

## Boundary com o resto

- **Cloudflared ingress rules** (que subdomínio → que container interno) vivem em `compose/stacks/h-cloudflared/config.yml`, NÃO aqui.
- **DNS local AdGuard** (resolução LAN-side) vive em `compose/stacks/adguard/config/AdGuardHome.yaml`.
- **Restic config interna** vive em `compose/stacks/h-restic/`.

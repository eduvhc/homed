# tofu/

OpenTofu para tudo o que é Cloudflare/R2 do homed.

## Layout

Prefixo `_` agrupa ficheiros de **setup/meta** (providers, encryption, vars, outputs)
no topo do `ls`. Ficheiros de **recursos cloud** ficam por baixo, um por concern.

```
tofu/
├── _providers.tf            # providers + version pinning
├── _encryption.tf           # state encryption nativo Tofu 1.10+
├── _variables.tf            # inputs (CF creds, IDs, defaults)
├── _outputs.tf              # outputs (sensitive: tunnel_token, r2_endpoint)
├── dns.tf                   # CNAME records *.iedora.com → tunnel
├── tunnel.tf                # Zero Trust Tunnel + token data source
├── r2.tf                    # bucket + lifecycle (180d fallback expiry)
├── .gitignore               # exclui .terraform/ e crash logs
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
   task encrypt NAME=h-restic
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
task tofu-init                # primeira vez (descarrega providers)
task tofu-plan                # mostra mudanças propostas
task tofu-apply               # aplica
task tofu-sync-secrets        # exporta tunnel_token para secrets/h-cloudflared.env (encriptado in-place)
```

**O que está em cache no keychain:**
- `CLOUDFLARE_API_TOKEN` — adicionado por ti
- `HOMED_TOFU_ENCRYPTION` — gerado automaticamente no primeiro `task tofu-*` para encriptar o state

**O que vem da CF API em runtime (não persistido):**
- `cf_account_id` (descoberto de `/accounts`)
- `cf_zone_id` (descoberto de `/zones?name=iedora.com`)

## Para Linux (Beelink)

macOS Keychain não existe em Linux. Antes de correr no Beelink, exportar via:
```bash
export CLOUDFLARE_API_TOKEN="<token>"
export HOMED_TOFU_ENCRYPTION="<passphrase gerado no Mac>"
```
(ou alternativa: gravar em sops `secrets/tofu.env` e ajustar Taskfile com fallback).
Por agora, Tofu corre apenas no portátil — apply via internet, sem necessidade de tofu no Beelink.

## Boundary com o resto

- **Cloudflared ingress rules** (que subdomínio → que container interno) vivem em `compose/stacks/h-cloudflared/config.yml`, NÃO aqui.
- **DNS local AdGuard** (resolução LAN-side) vive em `compose/stacks/adguard/config/AdGuardHome.yaml`.
- **Restic config interna** vive em `compose/stacks/h-restic/`.

# homed

Homelab declarativo: Docker Compose para apps, OpenTofu para Cloudflare/R2,
Ansible para bootstrap da máquina, SOPS+age para secrets.

## Estrutura

```
tofu/                     Cloudflare DNS, Tunnel, R2 — gerido por OpenTofu
compose/
  compose.yaml            Top-level; só `include:` + networks externas
  stacks/h-<svc>/         Cada serviço: compose.yaml [+ runtime.yaml /
                          init.yaml / backups.yaml / compose.bootstrap.yaml]
secrets/                  *.env encriptados in-place com sops+age
ansible/                  provision.yml (bootstrap declarativo da máquina)
Taskfile.yaml             Root tasks (lifecycle); módulos em .taskfiles/
.taskfiles/               secrets|build|restic|tofu — SRP por domínio
.sops.yaml                Regras de encriptação sops+age
docs/
  compose-standard.md     Padrão obrigatório dos composes (layout + regras)
  architecture.html       Diagrama de arquitectura
```

Layout flat — sem categorias intermédias (`infra/`/`ops/`/`arr/`). Cada
serviço é o seu próprio domínio. Detalhes do padrão em
[`docs/compose-standard.md`](docs/compose-standard.md).

## Convenção de nomes

Todos os serviços homelab são prefixados com `h-` (container, service-name
e folder). Ex: `h-auth`, `h-adguard`, `h-navidrome`. Identifica
imediatamente o que pertence ao stack na lista de containers.

## Bring-up numa máquina nova (runbook)

Cross-OS (macOS, Linux, Windows WSL2). Zero ficheiros pré-existentes —
credenciais saem de **Bitwarden Secrets Manager** via `bws`; versões das
CLIs vêm de **mise** (`.mise.toml` na raiz).

```bash
# 1. Operador (qualquer OS): instalar mise + exportar credenciais bws
curl -fsSL https://mise.run | sh
export BWS_ACCESS_TOKEN=<machine-account-token>
export HOMED_BWS_PROJECT_ID=<project-uuid>

# 2. Clone + tools pinned
git clone <repo-url> ~/homed && cd ~/homed
mise trust                             # 1ª vez (segurança nativa do mise)
mise install                           # sops, age, task, opentofu, bws, jq (~30s)

# 3. ansible: instalar separado (não é pin do .mise.toml)
#    macOS via nix-darwin já tem. WSL2/Linux: pipx install ansible
#    (justificação: ansible push-only, evita pipx/Python no .mise.toml)

# 4. Age key + provision do servidor
task secrets:bootstrap-age-key         # bws → ~/.config/sops/age/keys.txt (operator)
task provision HOST=beelink            # ansible: docker, mise + tools, tailscale, copy age key
task tofu CMD=apply                    # CF tunnel/DNS/R2 (state encriptado, vars de bws)

# 5. Servidor: arranca o stack (SSH ao Beelink)
ssh beelink
cd ~/homed && task up PROFILE=bootstrap    # decrypt + build + compose --profile bootstrap
```

Beelink nunca toca em bws — a age key chega-lhe via `ansible.builtin.copy`.
Versões das CLIs no Beelink vêm de `mise install` corrido pelo provision.
`task up PROFILE=bootstrap` corre o profile `bootstrap` (PAT/webhook do
Forgejo, seed do doco-cd, init do Postgres). Em re-runs diários usa `task up`.

## Operação diária

```bash
task up                                                            # tudo
task down                                                          # pára o stack
task validate                                                      # docker compose config (frio, sem subir)
docker compose -f compose/compose.yaml up -d h-adguard             # um só
task ps                                                            # estado dos containers
task logs NAME=h-auth                                              # tail logs
```

## Secrets (SOPS + age)

`secrets/*.env` ficam encriptados **in-place** (não há `.env.sops`
paralelos). Workflow:

```bash
task secrets:decrypt                   # decifra todos in-place (idempotente)
task secrets:edit NAME=h-auth          # sops abre, edita, re-encripta
task secrets:lock                      # encripta tudo (correr antes de commit, cobre novos)
task secrets:rotate                    # re-encripta com lista atual de recipients
```

`.sops.yaml` define as recipient keys (YubiKey + age offline backup).

## Serviços

| Serviço | Imagem | Função | Porquê este |
|---|---|---|---|
| `h-proxy` | lucaslorentz/caddy-docker-proxy | Reverse proxy + auto-TLS | Caddy auto-emite Let's Encrypt; docker-proxy descobre containers via labels → zero config drift; alternativa Traefik mas Caddyfile é mais legível |
| `h-cloudflared` | cloudflare/cloudflared | Cloudflare Tunnel | Expor à net sem abrir portas no router; gerido por Tofu (config_src: cloudflare) — routes em git, token único |
| `h-valkey` | valkey/valkey | Redis-compatible cache/session store | Authelia precisa de Redis para sessions multi-worker; Valkey é fork open-source pós Redis-license-change |
| `h-auth` | authelia/authelia | OIDC + ForwardAuth SSO | Standard 2026 self-hosted; OpenID Certified; ForwardAuth (apps sem OIDC nativo) + OIDC nativo na mesma stack |
| `h-postgres` | postgres + pg_dumpall (backups.yaml) | DB partilhada + dump consistente | Backend de Forgejo/Authelia/etc; o `backups.yaml` produz dumps em `/data/h-postgres/` que h-restic apanha |
| `h-doco-cd` | kimdre/doco-cd | GitOps agent para Compose | Reconcilia stacks a partir do Forgejo (profile=bootstrap no 1º run para seed) |
| `h-forgejo` | codeberg.org/forgejo + `forgejo-bootstrap:2.0.0` (build local) | Git forge self-hosted | Substitui GitHub para o repo `homed`; init faz db/admin/OIDC, bootstrap (opt-in) faz PAT + webhook para doco-cd |
| `h-adguard` | adguard/adguardhome | DNS sinkhole + ad-blocker LAN | Modernização Pi-hole (UI melhor, DoH/DoT nativo, regex filters). Router da casa aponta para o IP do Beelink |
| `h-whoami` | traefik/whoami | Health/debug echo server | Smoke test do proxy/SSO/network; remove quando confirmares que tudo passa |
| `h-navidrome` | deluan/navidrome | Subsonic API music server | Lê de `/music`, app móvel decente (Symfonium/play:Sub), single binary, low-RAM. Standard self-hosted Subsonic 2026 |
| `h-qbittorrent` | lscr/qbittorrent | BitTorrent downloader | Pega torrents do Lidarr; UI web; padrão de facto |
| `h-prowlarr` | lscr/prowlarr | Indexer manager | Configura trackers/Usenet uma vez, propaga (via `apps sync`) para Lidarr/futuros Sonarr |
| `h-lidarr` | lscr/lidarr | Music monitor + downloader orchestrator | Procura álbuns/artistas, importa para `/music` quando completos; pareado com Navidrome |
| `h-glances` | nicolargo/glances | Host stats (CPU/RAM/IO/net) | API HTTP consumível pelo widget do `h-dashboard`; muito mais leve que Prometheus+Grafana |
| `h-dashboard` | gethomepage/homepage | Página inicial com bookmarks | Single pane of glass para URLs/status de todos os serviços |
| `h-yt-dlp` | `homed/h-yt-dlp:2.0.0` (build local, base `python:3.14-alpine`) | Download de áudio/vídeo do YouTube | yt-dlp + ffmpeg; alimenta `/music/_downloads/` que Lidarr ignora; útil para álbuns indisponíveis em trackers |
| `h-restic` | mazzolino/restic | Cron de backups → R2 | Encrypted, dedup, fast restic; container automatiza schedule + retention; R2 destino (mesmo tofu provider que tunnel) |
| `h-gatus` | twin/gatus | Uptime/health monitoring | Health checks declarativos por serviço; status page consumível pelo dashboard |

Imagens custom (build local, pinned):

- `forgejo-bootstrap:2.0.0` — multiplex admin/oidc/config/PAT/webhook
- `homed/h-yt-dlp:2.0.0` — yt-dlp + ffmpeg sobre `python:3.14-alpine`
- `h-bootstrap-db:1.0.0` — init helper para Postgres (criar DB/role por app)

Targets: `task build:forgejo-bootstrap`, `task build:h-yt-dlp`,
`task build:bootstrap-db`. Re-correm automaticamente quando os sources
mudam (Taskfile `sources:`).

## Adicionar um serviço

1. `mkdir compose/stacks/h-<nome>` e cria `compose.yaml` (ENTRY).
   Opcionais conforme a complexidade do serviço:
   - `runtime.yaml` — long-running services (`restart: unless-stopped`)
   - `init.yaml` — one-shots (`service_completed_successfully`)
   - `backups.yaml` — backup-prep (DB dump, export estruturado)
   - `compose.bootstrap.yaml` — opt-in via `profile=bootstrap`
2. Se tem secrets: cria `secrets/h-<nome>.env` em plaintext + `task secrets:lock` (encripta todos os plaintexts, incluindo o novo).
3. Adiciona a linha em `compose/compose.yaml` no bloco `include:`.
4. `task validate` (sanity check a frio) → `task up` (ou
   `docker compose -f compose/compose.yaml up -d h-<nome>` para só um).

Regras do padrão (cap 80L por file, naming dos fragments, anchors
file-scoped, shell ≤10 linhas) em
[`docs/compose-standard.md`](docs/compose-standard.md).

## Tofu (Cloudflare + R2)

```bash
task tofu CMD=init                     # inicializa providers
task tofu CMD=plan                     # plan
task tofu CMD=apply                    # apply (state encriptado)
task tofu:sync-secrets                 # output tunnel_token → secrets/h-cloudflared.env encriptado
```

State encriptado com `HOMED_TOFU_ENCRYPTION` lido do Bitwarden Secrets
Manager (logic em `.taskfiles/tofu.yaml`).

## Restic (backups → R2)

```bash
task restic:snapshot                   # snapshot manual agora (com hooks pre/post)
task restic:restore SNAP=latest TARGET=/tmp/restore
task restic -- snapshots --compact     # CLI passthrough — listar
task restic -- check                   # CLI passthrough — integridade
task restic -- stats --mode raw-data   # CLI passthrough — tamanho/dedup
```

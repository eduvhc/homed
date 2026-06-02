# homed

Homelab declarativo: Docker Compose para apps, OpenTofu para Cloudflare/R2.

## Estrutura

```
tofu/                     Cloudflare DNS, Tunnel, R2 — gerido por OpenTofu
compose/
  compose.yaml            Top-level; só `include:` + networks
  _common.yaml            YAML anchors (restart, logging, security_opt)
  stacks/<cat>/<svc>/     Cada serviço: compose.yaml [+ config/] [+ env.sops]
scripts/                  provision.sh, restore.sh, backup-test.sh
.sops.yaml                Regras de encriptação sops+age
```

## Bring-up numa máquina nova (runbook)

```bash
# 1. Debian 12 net-install
# 2. Importar chave age (YubiKey ou ficheiro offline)
git clone <repo-url> ~/homed && cd ~/homed
./scripts/provision.sh                 # docker, restic, sops, tailscale
cd tofu && tofu apply                  # tunnel creds, R2, DNS
./scripts/restore.sh latest            # restic pull do R2 (config + volumes)
docker compose -f compose/compose.yaml up -d
```

## Operação diária

```bash
docker compose -f compose/compose.yaml up -d                # tudo
docker compose -f compose/stacks/arr/sonarr/compose.yaml up -d --no-deps   # um serviço
docker compose -f compose/compose.yaml config               # valida YAML consolidado
```

## Serviços (e porquê cada um)

| Categoria | Serviço | Imagem | Função | Porquê este |
|---|---|---|---|---|
| **infra** | `h-auth` | authelia/authelia | OIDC + ForwardAuth SSO | Standard 2026 self-hosted; OpenID Certified; suporta ForwardAuth (apps sem OIDC nativo) + OIDC nativo (apps que suportam) com a mesma stack |
| **infra** | `h-proxy` | lucaslorentz/caddy-docker-proxy | Reverse proxy + auto-TLS | Caddy auto-emite Let's Encrypt; docker-proxy descobre containers via labels → zero config drift; alternativa Traefik mas Caddyfile é mais legível |
| **infra** | `h-cloudflared` | cloudflare/cloudflared | Cloudflare Tunnel | Expor à net sem abrir portas no router; gerido por Tofu (config_src: cloudflare) — routes em git, token único |
| **infra** | `h-valkey` | valkey/valkey | Redis-compatible cache/session store | Authelia precisa de Redis para sessions multi-worker; Valkey é fork open-source pós Redis-license-change |
| **network** | `h-adguard` | adguard/adguardhome | DNS sinkhole + ad-blocker LAN | Modernização Pi-hole (UI melhor, DoH/DoT nativo, regex filters). Aponta router da casa para o IP do Beelink |
| **media** | `navidrome` | deluan/navidrome | Subsonic API music server | Lê de `/music`, app móvel decente (Symfonium/play:Sub), single binary, low-RAM. Standard self-hosted Subsonic 2026 |
| **arr** | `h-lidarr` | lscr/lidarr | Music monitor + downloader orchestrator | Procura álbuns/artistas, importa para `/music` quando completos; pareado com Navidrome (Subsonic) |
| **arr** | `h-prowlarr` | lscr/prowlarr | Indexer manager | Configura trackers/Usenet uma vez, propaga (via `apps sync`) para Lidarr/futuros Sonarr. Sem ele cada *arr precisa configurar indexers separados |
| **arr** | `h-qbittorrent` | lscr/qbittorrent | BitTorrent downloader | Pega torrents do Lidarr; UI web; padrão de facto |
| **ops** | `h-dashboard` | gethomepage/homepage | Página inicial com bookmarks | Single pane of glass para todas as URLs dos serviços; widgets de status; substitui markdown no `bookmarks.md` |
| **ops** | `h-glances` | nicolargo/glances | Host stats (CPU/RAM/IO/net) | API HTTP consumível pelo `h-dashboard` widget; muito mais leve que Prometheus+Grafana |
| **ops** | `h-restic` | mazzolino/restic | Cron de backups → R2 | Encrypted, dedup, fast restic; container automatiza schedule + retention; R2 destino (mesmo tofu provider que tunnel) |
| **ops** | `h-yt-dlp` | homed/h-yt-dlp (build local) | Download de áudio/vídeo do YouTube | Image construída local com yt-dlp + ffmpeg; alimenta `/music/_downloads/` que Lidarr ignora; útil para álbuns indisponíveis em trackers |
| **ops** | `h-whoami` | traefik/whoami | Health/debug echo server | Standard smoke test do proxy/SSO/network; remove quando confirmares que tudo passa |

## Convenção de nomes

Todos os serviços homelab são prefixados com `h-` (container, service-name e folder). Ex: `h-auth`, `h-adguard`, `h-navidrome`. Identifica imediatamente o que pertence ao stack na lista de containers.

## Adicionar um serviço

1. `mkdir compose/stacks/<categoria>/h-<nome>` e cria `compose.yaml` (+ `config/` se precisa, + `env.sops` se tem secrets).
2. Adiciona uma linha em `compose/compose.yaml` no bloco `include:`.
3. `docker compose -f compose/compose.yaml up -d <nome>`.

## Verificação

Ver secção "Verificação (golden path)" em `~/.claude/plans/analisa-este-plano-infraestrutura-homela-curried-snowflake.md`.

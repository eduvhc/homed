# h-deploy

Webhook receiver para deploys auto-hospedados. Recebe POST de GitHub/Forgejo/Gitea, valida HMAC SHA-256, executa shell scripts que fazem `git pull` + `docker build` + `docker compose up`.

## Build

```sh
task build-deploy
```

Resulta em `h-deploy:1.0.0` no daemon Docker local (~50 MB, Alpine + docker CLI + git + webhook binary).

## Endpoints expostos

| URL | Hook id | Quem chama | Output |
|---|---|---|---|
| `https://deploy.iedora.com/hooks/homed-push` | `homed-push` | GitHub webhook de `eduvhc/homed` | `git pull` + `compose up -d` |
| `https://deploy.iedora.com/hooks/app-build` | `app-build` | GitHub webhook de cada monorepo de app | `git pull` + `docker build` + `compose up <app>` |
| `https://deploy.iedora.com/hooks/health` | `health` | Gatus probe | `200 {"status":"ok"}` |

**Auth:** HMAC SHA-256 (`X-Hub-Signature-256`) com secret per-hook. Sem Authelia (webhooks não conseguem fazer login).

## Setup inicial (1×)

### 1. Gerar SSH deploy key

```sh
ssh-keygen -t ed25519 -f ~/homed/secrets/keys/id_ed25519_deploy -N '' -C 'homed-deploy'
chmod 600 ~/homed/secrets/keys/id_ed25519_deploy
ssh-keyscan github.com > ~/homed/secrets/keys/known_hosts
```

Copia a chave **pública** (`id_ed25519_deploy.pub`) para:
- **Settings → Deploy keys** do repo `eduvhc/homed` (read-only, sem write access)
- **Settings → Deploy keys** do `lyzer-monorepo` (read-only)

### 2. Gerar secrets HMAC

```sh
echo "WEBHOOK_SECRET_HOMED=$(openssl rand -hex 32)" >  ~/homed/secrets/h-deploy.env
echo "WEBHOOK_SECRET_APP=$(openssl rand -hex 32)"   >> ~/homed/secrets/h-deploy.env
echo "GATUS_TOKEN=<copy from secrets/h-restic.env>" >> ~/homed/secrets/h-deploy.env
chmod 600 ~/homed/secrets/h-deploy.env
task encrypt NAME=h-deploy
```

### 3. Criar webhooks no GitHub

Para `eduvhc/homed`:
- **Settings → Webhooks → Add webhook**
- Payload URL: `https://deploy.iedora.com/hooks/homed-push`
- Content type: `application/json`
- Secret: valor de `WEBHOOK_SECRET_HOMED` (vê com `task edit NAME=h-deploy`)
- Events: **Just the push event**

Para cada repo de app (ex.: `lyzer-monorepo`):
- Mesma config mas:
  - URL: `https://deploy.iedora.com/hooks/app-build`
  - Secret: `WEBHOOK_SECRET_APP`

### 4. DNS e tunnel

```sh
# adiciona "deploy" a subdomains em tofu/dns.tf
task tofu-apply
```

### 5. Build e arranque

```sh
task build-deploy
task up
```

### 6. Smoke test

```sh
# health (sem auth)
curl https://deploy.iedora.com/hooks/health
# → {"status":"ok"}

# trigger manual de homed-push (vai falhar HMAC, mas testa routing)
curl -X POST https://deploy.iedora.com/hooks/homed-push \
     -H "Content-Type: application/json" \
     -d '{"ref":"refs/heads/main"}'
# → 200 with empty body (hook executou; vê logs em data/deploy/homed.log)
```

Real test: GitHub UI → **Webhooks → Redeliver** num delivery passado.

## Rollback

Cada build tagga `:latest` + `:sha-<short>`. Mantemos as 5 últimas SHAs.

```sh
# 1. Listar SHAs disponíveis
docker images lyzer/lyzer-monorepo --format '{{.Tag}}\t{{.CreatedAt}}'

# 2. Editar compose/stacks/apps/<app>/compose.yaml:
#    image: lyzer/lyzer-monorepo:sha-abc1234   (em vez de :latest)

# 3. Aplicar
task up
```

Atalho: `task rollback APP=lyzer-monorepo SHA=abc1234`.

## Logs

```sh
task deploy-logs                    # tail -f de data/deploy/{homed,app}.log
docker compose logs -f h-deploy     # logs do webhook receiver
```

Cada deploy escreve uma linha com timestamp ISO no log respectivo.

## Phase 2 (quando >2 services em produção)

Quando a complexidade cresce, **migrar para Forgejo Actions + registry OCI built-in**:

1. Auto-hospedar Forgejo no homelab (`stacks/infra/h-forgejo/`).
2. Espelhar repos do GitHub para Forgejo (ou migrar de vez).
3. CI corre em Forgejo Actions runner local — build + push para `forgejo.iedora.com/lyzer/web:sha-X`.
4. h-deploy passa a fazer só `docker compose pull && up`, sem build.

Vantagens: builds reprodutíveis e cacheáveis no registry, rollback via tag pull em vez de rebuild, working tree do source code fora do servidor de produção. A surface area do h-deploy reduz para um simples puller.

## Trade-offs aceites

- **Docker socket = root no host.** Mitigado por HMAC + tunnel exclusivamente. Não correr nada não-confiável neste container.
- **Build durante deploy bloqueia CPU.** OK para homelab; pior para SaaS com utilizadores reais (mover para Phase 2 quando isso doer).
- **Sem rollback automático.** Manual via `task rollback`. Forward-only por design.
- **Mirror do homed read-only no container.** O git pull faz-se num espelho em `/workspace/homed`; o working tree real no host actualiza-se via `docker compose -f /homed/...` que lê o que já está no host. O working tree do host actualiza-se separadamente (cron, ou `task self-pull`).

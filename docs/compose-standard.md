# Compose standard

Padrão obrigatório para composes do homed. Otimizado para LLM-readability
(custo de tokens) e para humano que precisa de localizar 1 propriedade
em 30 segundos.

## Layout

Sem categorias intermédias — domain ownership por directório de serviço.

```
compose/
├── compose.yaml              # ROOT — networks externas + include: dos entries
└── stacks/<serviço>/
    ├── compose.yaml          # ENTRY — include: fragments + volumes + networks
    ├── runtime.yaml          # long-running services
    ├── init.yaml             # one-shot (service_completed_successfully)
    ├── backups.yaml          # backup concerns deste serviço (dump, snapshot prep)
    └── compose.bootstrap.yaml # opt-in via profile=bootstrap (PAT, webhooks, seed)
```

Cada concern do serviço vive na sua própria directoria. Backups do Postgres
ficam em `h-postgres/backups.yaml`, não em `h-restic` — h-restic é só o
engine que consome os outputs dos `backups.yaml`.

## Regras

1. **Cap de 80 linhas por compose file**. Inclui comentários. Se ultrapassar,
   splitar em fragments via `include:`.

2. **Serviços simples (1 runtime + 0-1 init) ficam em `compose.yaml` único**.
   Não criar fragments só por simetria — é ruído.

3. **Anchors são file-scoped**. Quando partilhados por N services em ficheiros
   separados: ou duplicam (preferido se 2-3 linhas), ou ficam todos no mesmo
   fragment.

4. **Naming canónico dos fragments**:
   - `runtime.yaml` — long-running, `restart: unless-stopped`
   - `init.yaml` — `restart: "no"`, `service_completed_successfully`
   - `backups.yaml` — backup-prep deste serviço (só necessário se os dados
     precisam de prep antes de poderem ser snapshotados — e.g., DB dump
     consistente, export estruturado). Output vai para `/data/<svc>/`.
   - `compose.bootstrap.yaml` — opt-in, `profile=bootstrap` (decisão 20)

   **Modelo de backups (decoupled)**: a app declara *o que* (escreve em
   `/data/<svc>/`). O h-restic engine monta `/data` umbrella + snapshota
   tudo. Adicionar serviço não requer tocar em h-restic. Ficheiros
   already-on-disk em `/data/` não precisam de `backups.yaml` — são
   apanhados automaticamente.

5. **Networks `external: true` declarados em cada file que os usa**, para
   permitir validação standalone (`docker compose -f runtime.yaml config`).

6. **Volumes nomeados declarados no entry**. Fragments só referenciam.
   Top-level merge do `include:` agrega.

7. **env_file paths relativos ao file que faz a referência**. Profundidade:
   `../../../secrets/<stack>.env` (3 ups: stacks/<svc>/file.yaml → root).

8. **Anchors cross-file são proibidos.** `include:` NÃO propaga YAML anchors
   (file-scoped no parser, antes do merge). Verificado contra compose-spec
   `14-include.md` + 5 canonicals (Mastodon, Immich, Authentik, Outline,
   Mealie) — **zero** usam anchors cross-file.

9. **Duplicação ≤4 linhas entre services é aceitável** (`security_opt`,
   `restart`, `logging`, labels Caddy). Promover a anchor só quando ≥5
   linhas E ≥3 services no mesmo file.

10. **Env blocks com ≥15 settings configuráveis → config file mountado**
    (e.g., `./config/app.ini`, `./config/configuration.yml`). Env vars do
    compose ficam só para overrides em runtime (secrets via env_file).
    Ver `h-forgejo/config/app.ini` (single source of truth para 27 settings)
    + `h-auth/config/configuration.yml`.

11. **Healthcheck HTTP pattern**: template canónico repetido nos services
    (NÃO factorizar — copy-paste de 5L mantém grep-ability):
    ```yaml
    healthcheck:
      test: ["CMD", "wget", "-q", "--spider", "http://localhost:PORT/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s
    ```

12. **Labels Caddy**: 3 linhas idiomáticas (`caddy:`, `caddy.import:`,
    `caddy.reverse_proxy:`) — copy-paste em cada service exposto. NÃO
    factorizar — perdes grep-ability ("onde está o vhost de qb?").

13. **Cap de 30 includes na root `compose.yaml`**. Acima → splitar por
    eixo *funcional* (não taxonómico): e.g., `compose/lyzer.yaml` para o
    monorepo Lyzer (apps comerciais), root para infra+ops do homed.

## Excepções documentadas ao cap 80L

- `h-restic/runtime.yaml` (~75L): 3 restic services partilham `x-restic-base`.
  Aceito — anchors file-scoped.

Todos os outros files ≤80L. Se passar, refactor (shell → custom image,
serviços não relacionados → fragments).

## Shell em composes

Convenções para init/bootstrap containers (verificado contra Mastodon,
Authentik, Nextcloud, Immich, Forgejo upstream — todos têm **zero** inline
heredocs nos seus composes).

1. **Cap de shell inline: ≤10 linhas**. Acima → custom image.
   Inline >10L é upstream-unattested em todos os projectos auditados.

2. **`["/bin/sh","-c","..."]`**, nunca `entrypoint: [list] + command: |block`.
   Compose-spec: block scalar como `command:` vira **single positional arg**;
   só a 1ª linha chega ao `sh -c`, resto leaka como `$0/$1/...`.

3. **`$$VAR` para escapar interpolação Compose**. `$VAR`/`${VAR}` são
   substituídos por Compose antes do container ver. `.env` quoting: single =
   literal, double/unquoted = interpolado (oposto do shell).

4. **`set -eu` (POSIX sh)**, nunca `pipefail` sem `bash`. Alpine `sh` é
   busybox: sem `pipefail`, sem `[[ ]]`, sem arrays. Se precisas, `apk add
   --no-cache bash` e `#!/usr/bin/env bash; set -euo pipefail`.

5. **Custom image multiplex por env var** quando ≥2 steps partilham base.
   Padrão: `BOOTSTRAP_STEP=admin|oidc|config` + `exec /steps/$BOOTSTRAP_STEP.sh`.
   Ver `compose/stacks/h-forgejo/bootstrap/` (3 steps, base forgejo + curl/jq).

## Anti-padrões

- **Categorias intermédias** (`infra/`, `ops/`, `arr/`) — criam confusão de
  domínios (e.g., backup do Postgres acabaria em `ops/`, mas o owner é
  `h-postgres`). Cada serviço é o seu próprio domínio.
- `extends:` — substituído por anchors + include
- `compose.override.yaml` — homelab não tem dev/prod split
- Profiles para env separation — profiles só para bootstrap/seed
- Cross-file anchors (não existem em YAML; usar fragment + include)

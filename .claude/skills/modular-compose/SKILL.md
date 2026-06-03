---
name: modular-compose
description: |
  Design, audit, and refactor declarative Docker Compose architectures
  that scale without becoming unmaintainable monoliths. Enforces a
  source-verified standard: per-service SRP, ≤80 LoC compose files,
  fragment-based modularity (runtime/init/backups), idempotent init
  containers, custom-image multiplex for shell, and the umbrella `/data`
  decoupling pattern for backup engines. Use this skill whenever the user
  works on Docker Compose architecture, multi-service orchestration,
  homelab setup or refactor, "big composes" (>100 LoC), service onboarding,
  init container patterns, backup/restore strategy in compose, shell logic
  in compose files, GitOps loops with compose, or any task that touches
  multiple compose files in the same repository. Always triggers on
  mentions of compose `include:`, fragment patterns (runtime.yaml,
  init.yaml, backups.yaml, bootstrap), SOPS+compose, supercronic in
  containers, or "this compose file is getting too big". Applies in
  3 contexts, in this order of priority: (1) audit existing services,
  (2) design new services, (3) maintain ongoing changes.
---

# Modular Compose

A declarative, source-verified standard for Docker Compose architectures that grow to 20+ services without rot. Distilled from auditing real production-grade homelabs against the canonical projects (Mastodon, Immich, Authentik, Nextcloud, Forgejo, doco-cd, mazzolino/restic) by reading their actual source code, not blog posts.

## Core philosophy — non-negotiable

Five principles. Each is a tie-breaker when refactoring or designing.

1. **100% declarative.** Every state expressible in a version-controlled file. No "remember to chmod after pulling." If a step is needed, it lives in `Taskfile.yaml`, a `Dockerfile`, or a compose `init` container — never in a tribal-knowledge README step.

2. **Idempotent.** Every action (init container, task target, bootstrap script) safe to re-run. Init containers use `NOT EXISTS` SQL guards, file-existence checks, or CLI `list | grep -qx` patterns. The repo can be applied to a fresh machine OR a partially-applied machine with the same outcome.

3. **SRP per directory.** Each service directory owns ALL its concerns: runtime, init, backup-prep, bootstrap. Cross-cutting consolidation (`ops/` for backups, `secrets/` for keys) creates domain confusion when the backup of Postgres should logically live with Postgres, not with the backup engine.

4. **Scalable without coupling.** Adding service N+1 must not require editing service N. Backup engine mounts `/data` umbrella read-only; new services that write to `/data/<svc>/` are auto-covered. Init pattern uses generic reusable images (`h-bootstrap-db:1.0.0`) that any new app instantiates with env vars, never per-app forks.

5. **Source-verified, not blog-verified.** Before adopting a pattern, clone the upstream repo and read the actual code. Web search and ChatGPT answers go stale within months. CLI flags, config keys, and default behaviors live in the source — verify there.

## The 3-context workflow

Apply this skill in this exact priority order:

### Context 1: Audit existing services (highest priority)

When asked to "improve the compose setup" or similar:
1. Inventory current state: `wc -l` every compose file; `rg` for anti-patterns (`:latest`, `privileged: true`, inline shell heredocs, missing healthchecks).
2. Map every service against the standard below — produce a smell table per service.
3. Prioritize by **severity × cost**: a 1-line `security_opt` fix on 5 services beats a 200-line refactor of 1 service.
4. Apply HIGH then MED, defer LOW with rationale.

### Context 2: Design new service

When adding a service to an existing stack:
1. Determine fragment shape. Start with the question: "How many concerns does this service have?"
   - 1 runtime, no init: single `compose.yaml`. Done.
   - 1 runtime + 1 init: keep in `compose.yaml` if total ≤80L; otherwise split into `compose.yaml` (entry) + `runtime.yaml` + `init.yaml`.
   - 1 runtime + multi-init + backup-prep: full fragment set.
2. Research the service's canonical compose example (web + source clone). Cite the upstream file you read.
3. Write the compose. Verify size never exceeds 80L per file. Validate with `task validate` (or `docker compose config -q`).

### Context 3: Maintain ongoing changes

When refactoring or adding a feature to an existing service:
1. Single-file principle: a config change to one service touches only that service's files.
2. Validate after every change. Standard requires `docker compose config -q` clean before commit.
3. Update related docs (README, architecture.html) inline — never separately, never deferred.

## The standard — 13 rules

Verified source-level against compose-spec + 5 canonical projects.

### Layout & structure

**Rule 1 — Cap of 80 LoC per compose file (hard rule).**
Why: mediana upstream verificada (Mastodon 189L is kitchen-sink with 5 services ≈ 38L/svc; Immich 89L total; Authentik 67L; doco-cd prod 41L). Files >80L always become file-skimming hostile. Splitar via `include:` quando ultrapassa.

**Rule 2 — Simple services stay single-file.**
1 runtime + 0-1 init: `compose.yaml` único. Não criar `runtime.yaml`/`init.yaml` fragments só por simetria — é ruído.

**Rule 3 — Anchors são file-scoped, SEMPRE.**
`include:` NÃO propaga YAML anchors (verificado em compose-spec `14-include.md`: "all resources definitions are copied" — só *resource definitions* são merged; YAML anchors são resolvidos pelo parser ANTES do compose ver o documento). Quando partilhados N≥3 services no mesmo file: anchor. Cross-file: NUNCA — duplicar ou refactorar.

**Rule 4 — Naming canónico dos fragments.**
- `runtime.yaml` — long-running services, `restart: unless-stopped`
- `init.yaml` — `restart: "no"` + `service_completed_successfully`
- `backups.yaml` — backup-prep deste serviço (só necessário se data precisa de prep antes de snapshot, e.g., DB dump consistente)
- `compose.bootstrap.yaml` — opt-in via `profile=bootstrap` (PAT/webhook seed, one-shot in fresh-machine)

**Rule 5 — Networks `external: true` declarados em cada file que os usa.**
Permite validação standalone (`docker compose -f runtime.yaml config`). Não confiar em merge para fragments.

**Rule 6 — Volumes nomeados declarados no entry.** Fragments só referenciam. Top-level merge do `include:` agrega.

**Rule 7 — env_file paths relativos ao file que faz a referência.** Layout flat → `../../../secrets/<stack>.env` (3 ups: `stacks/<svc>/file.yaml` → repo root).

### Duplication tolerance

**Rule 8 — Duplicação ≤4 linhas entre services é aceitável.**
`security_opt`, `restart`, `logging`, labels Caddy — todos são 1-3L. Não factorizar. Promover a anchor só quando ≥5 linhas E ≥3 services no mesmo file. (Verificado: docker-restic-mazzolino repete env block 3× sem anchor — convergência community.)

**Rule 9 — Env blocks com ≥15 settings configuráveis → config file mountado.**
Compose env block fica só para overrides em runtime (secrets via env_file). Source-of-truth = `./config/app.ini`, `./config/configuration.yml`, etc. Exemplo: Forgejo upstream recomenda `app.ini` para config estática; env vars para secrets-substituídos.

**Rule 10 — Healthcheck HTTP pattern — copy-paste, NÃO anchor.**
```yaml
healthcheck:
  test: ["CMD", "wget", "-q", "--spider", "http://localhost:PORT/health"]
  interval: 30s
  timeout: 5s
  retries: 3
  start_period: 30s
```
5 linhas, idiomatic. Anchor perderia grep-ability ("onde está o probe de qb?").

**Rule 11 — Labels Caddy — copy-paste, NÃO anchor.**
3 linhas (`caddy:`, `caddy.import: authelia` se autenticado, `caddy.reverse_proxy: "{{upstreams N}}"`). Anchor perderia "onde vive o vhost de X?".

### Scaling root

**Rule 12 — Cap de 30 includes na root `compose/compose.yaml`.**
Acima → splitar por eixo *funcional* (não taxonómico): `compose/lyzer.yaml` para apps comerciais com lifecycle próprio, root continua flat para infra+ops do core stack.

**Rule 13 — Layout SEM categorias intermédias** (`infra/`, `ops/`, `arr/`, `network/`, `media/`).
Categorias criam confusão de domínios: backup do Postgres deveria ser `ops/h-postgres-dump/` ou `infra/h-postgres/backups.yaml`? SRP ganha — backup of Postgres lives in `h-postgres/backups.yaml`. Cada serviço é o seu próprio domínio.

## Shell em composes

Convenções verificadas contra Mastodon, Authentik, Nextcloud, Immich, Forgejo upstream — **zero** desses projectos tem inline heredocs nos seus composes.

**Rule SH-1 — Cap de shell inline: ≤10 linhas.** Acima → custom image. Inline >10L é upstream-unattested.

**Rule SH-2 — `["/bin/sh","-c","..."]` single-arg, NÃO `entrypoint: [list] + command: |block`.**
Compose-spec: block scalar como `command:` vira **single positional arg** para o entrypoint; só 1ª linha chega ao `sh -c`, resto leaka como `$0/$1/...`. Bug documentado.

**Rule SH-3 — `$$VAR` para escapar interpolação Compose.**
Compose substitui `$VAR`/`${VAR}` antes do container ver. `.env` quoting: single = literal, double/unquoted = interpolado (oposto da shell convention).

**Rule SH-4 — `set -eu` (POSIX sh), NUNCA `pipefail` sem bash.**
Alpine `sh` é busybox: sem `pipefail`, sem `[[ ]]`, sem arrays. Se necessário: `apk add --no-cache bash` + `#!/usr/bin/env bash; set -euo pipefail`.

**Rule SH-5 — Custom image multiplex por env var quando ≥2 steps partilham base.**
Padrão:
```
bootstrap/
├── Dockerfile           # FROM <base> + apk add deps + COPY scripts
├── entrypoint.sh        # case "$BOOTSTRAP_STEP" in admin) ...; oidc) ...; ... esac
└── steps/
    ├── admin.sh
    ├── oidc.sh
    └── config.sh
```
Cada compose service: `image: <name>:<semver>` + `environment: BOOTSTRAP_STEP: admin`. Image local pinada (`forgejo-bootstrap:2.0.0`, não `:latest`).

**Rule SH-6 — Cron em containers: supercronic, NÃO busybox crond.**
busybox crond exige `CAP_SETUID`/`SETGID` e lê `/etc/crontabs/root` (mode 600 root). Incompatível com `user: 1000:1000 + cap_drop: ALL`. Supercronic (Aptible v0.2.46+) corre como qualquer user, foreground, structured stdout. Pattern: `FROM <base> + curl supercronic + COPY crontab + ENTRYPOINT supercronic /etc/crontab`.

## Init containers

**Rule IC-1 — `restart: "no"` + `condition: service_completed_successfully`.** Pattern canónico, inalterado em 2025-2026 (compose-spec).

**Rule IC-2 — Idempotência via guards explícitos.** Nunca confiar em "isto só corre uma vez". Templates:
- DB role: `IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = X)`
- DB database: `WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = X) \gexec`
- File: `[ -s /path/to/file ] && echo "skip" || generate`
- CLI list: `cli list | grep -qx NAME && echo "skip" || cli create NAME`

**Rule IC-3 — Decision 20: quando promover init para `compose.bootstrap.yaml` (profile=bootstrap).**
Critério funcional (≥2 of 4):
- `build:` directive (image custom necessária)
- Profile-gated (opt-in)
- Cross-stack state (output consumido por outra stack via volume partilhado)
- New-machine seed (corre só em bring-up, não em re-deploys)

LoC NÃO é critério (init pequeno mas profile-gated → bootstrap; init grande mas always-run → init.yaml).

## Backups — decoupled umbrella

**Rule BK-1 — Per-service `backups.yaml`** define backup-prep desta service. Output escreve para `/data/<svc>/`. Adicionar service novo = escrever sob `/data/<svc>/`, **sem touch no backup engine**.

**Rule BK-2 — Backup engine** (h-restic, etc.) monta `/data:ro` umbrella. Snapshota tudo. Zero coupling cross-stack.

**Rule BK-3 — Backup engine single-container** (NÃO 3 containers per cron job).
mazzolino/restic 3-container pattern viola SRP por stack (3 containers idle 99% para 1 trabalho). Refactorar para single container + supercronic (rule SH-6) + dispatcher case (rule SH-5).

## Workflow de research source-verified

Antes de adoptar qualquer pattern:

1. **Web search** — current best practices via WebFetch / WebSearch. Output dura ~3 meses; tem que verificar source.

2. **Clone upstream** — `git clone` para `~/projects/references/<name>/`. Se o user já tem refs locais, ler de lá em vez de re-clonar.

3. **Read source code** — para CLI flags: `cmd/<name>.go` (Go) ou `bin/<name>` (Ruby/Py). Para config keys: `internal/configuration/schema/*.go` ou `app/models/configuration.rb`. Para defaults: tests (`*_test.go`).

4. **Cross-reference ≥2 canonicals** — pattern só é "canónico" se aparece em ≥2 projectos production-grade.

5. **Cite o ficheiro fonte no comentário do compose** — exemplo:
   ```yaml
   # Source: forgejo cmd/admin_auth_oauth.go:217 (addOauth cria auth_model.Source).
   ```

## Anti-padrões (verificados)

- **`extends:`** — substituído por anchors + include. Tem bugs conhecidos com include (docker/compose #12533).
- **`compose.override.yaml`** — homelab não tem dev/prod split; 1 source-of-truth.
- **Profiles para env separation** — profiles SÓ para bootstrap/seed.
- **Cross-file anchors** — não existem em YAML (file-scoped); usar fragments + duplicação.
- **Categorias intermédias** (`infra/`, `ops/`, etc.) — domain confusion.
- **`:latest` em images custom** — não-reproduzível.
- **`pip install --upgrade` em Dockerfile** — image diferente cada build.
- **`privileged: true`** — quase sempre evitável; flagged in audits.
- **Docker socket :rw** sem rationale documentado — passa 90% do trabalho.
- **busybox crond para non-root containers** — anti-pattern, usar supercronic.
- **Inline shell heredoc >10L** — extrair para custom image.
- **Mountar host scripts em upstream images** — couples deploy host ↔ repo layout.
- **`sleep N && app`** vs `depends_on: service_healthy` — race conditions.
- **Stack name ≠ container name** — confusão em `docker ps`, alerting, logs.
- **Backup engine que enumera sources explicitamente** — coupling; usar umbrella mount.

## Validação obrigatória

Após qualquer mudança:
1. `task validate` (ou `docker compose -f compose/compose.yaml --profile bootstrap config -q`)
2. Build local de images custom afectadas
3. Smoke test do entrypoint (`docker run --rm <image> --help` ou step-test)

Standard exige zero warnings em config -q antes de commit.

## Reference: a homed reference repository

O setup em `/Users/eduvhc/homed` (público em github.com/eduvhc/homed) é uma implementação completa deste standard — 19 services, single-container backup engine, multiplex bootstrap images, layout flat, declarative end-to-end. Quando em dúvida sobre pattern: ler o equivalente em h-* lá. Não copiar cegamente — confirmar ainda current via source.

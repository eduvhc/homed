# h-bootstrap-db

Container caseiro que cria `ROLE` + `DATABASE` em `h-postgres` antes de qualquer migration tool tocar na DB. Idempotente — re-executar é seguro.

## Quando usar

Em **cada** app SaaS nova que precise da sua própria DB partilhada do `h-postgres`. Pattern:

```
<app>-db-bootstrap (exit 0)  →  <app>-db-migrate (dbmate, exit 0)  →  <app>-app (long-running)
```

## Build

```sh
task build-bootstrap-db
```

Resultado: tag local `h-bootstrap-db:1.0.0` no daemon Docker. Re-build só quando `run.sh` muda.

## Adicionar uma app nova — checklist

Substituir `<app>` pelo nome (lowercase, sem hífens; é também o nome do role e da DB).

1. **Criar secret** `secrets/<app>.env` (plaintext) com:
   ```
   <UPPER_APP>_PASSWORD=<password forte>
   DATABASE_URL=postgres://<app>:<password>@h-postgres:5432/<app>?sslmode=disable
   # + qualquer env runtime da app (API_KEY, etc.)
   ```
   Depois: `task secrets:lock` (encripta todos os plaintexts in-place, incluindo o novo).

2. **Criar stack** `compose/stacks/<app>/compose.yaml`:

   ```yaml
   services:
     <app>-db-bootstrap:
       image: h-bootstrap-db:1.0.0
       restart: "no"
       container_name: <app>-db-bootstrap
       depends_on:
         h-postgres: { condition: service_healthy }
       env_file:
         - ../../../secrets/h-postgres-admin.env   # PGPASSWORD do superuser
         - ../../../secrets/<app>.env              # <UPPER_APP>_PASSWORD
       environment:
         DB: <app>
       networks: [internal]

     <app>-db-migrate:
       image: ghcr.io/amacneil/dbmate:2.27.0
       restart: "no"
       container_name: <app>-db-migrate
       depends_on:
         <app>-db-bootstrap: { condition: service_completed_successfully }
       env_file:
         - ../../../secrets/<app>.env
       environment:
         DBMATE_MIGRATIONS_DIR: /db/migrations
         DBMATE_NO_DUMP_SCHEMA: "true"
       volumes:
         # host path da pasta de migrations da app (monorepo, repo dedicado, etc.)
         - ${MIGRATIONS_HOST_PATH}:/db/migrations:ro   # exportado pelo operador (cross-OS)
       command: ["up"]
       networks: [internal]

     <app>-app:
       image: <registry>/<app>:<tag>
       container_name: <app>-app
       restart: unless-stopped
       depends_on:
         <app>-db-migrate: { condition: service_completed_successfully }
       env_file:
         - ../../../secrets/<app>.env
       networks: [internal, edge]
       labels:
         caddy: http://<app>.iedora.com
         caddy.import: authelia
         caddy.reverse_proxy: "{{upstreams 3000}}"

   networks:
     internal: { external: true }
     edge:     { external: true }
   ```

3. **Adicionar include** em `compose/compose.yaml`:
   ```yaml
   include:
     - stacks/<app>/compose.yaml
   ```

4. **Adicionar subdomínio** em `tofu/dns.tf` (variável `subdomains`), correr `task tofu CMD=apply`.

5. **Validar refs**: `rg "<app>" ~/dotfiles/modules/home/references.nix` — se a app é OSS upstream, adicionar.

6. `task up` → deploy completo. Primeira corrida: bootstrap + migrate correm (~5s cada), app arranca.

7. **Re-correr migrations isoladas**: `task migrate APP=<app>`.

## Apps com múltiplas DBs (ex.: Next.js monorepo)

Repetir os 2 sidecars (`-db-bootstrap` + `-db-migrate`) por DB, com nomes prefixados pela DB:

```yaml
services:
  core-db-bootstrap: { ..., environment: { DB: core } }
  core-db-migrate:   { ..., DATABASE_URL: postgres://core:...@h-postgres/core }
  imopush-db-bootstrap: ...
  imopush-db-migrate: ...
  meta-db-bootstrap: ...
  meta-db-migrate: ...
  lyzer-web:
    depends_on:
      core-db-migrate:    { condition: service_completed_successfully }
      imopush-db-migrate: { condition: service_completed_successfully }
      meta-db-migrate:    { condition: service_completed_successfully }
```

## Notas

- **Forward-only.** Não há `task migrate-down` por design. Rollback = nova migration que reverte. Para experimentar em dev, `docker compose run --rm <app>-db-migrate down`.
- **Idempotência.** Bootstrap re-corre em cada `compose up` — usa guards `NOT EXISTS`. Migrate idem (dbmate vê `schema_migrations`).
- **Password rotation.** `task secrets:edit NAME=<app>` (altera password in-place) → `psql -c "ALTER ROLE <app> WITH PASSWORD '<new>'"`. Bootstrap não rotaciona passwords.

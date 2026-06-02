#!/bin/sh
# h-bootstrap-db — cria ROLE + DATABASE para uma app, idempotente.
#
# Inputs (env vars):
#   DB                  nome da DB (e do role; assumimos role.name == db.name)
#   <UPPER_DB>_PASSWORD password do role (ex.: DB=imopush  →  IMOPUSH_PASSWORD)
#   PGHOST              default: h-postgres
#   PGUSER              default: postgres (superuser)
#   PGPASSWORD          password do superuser (vem de secrets/h-postgres-admin.env)
#
# Sai 0 sempre que a DB e o role já existem ou foram criados. Re-executar é seguro.

set -e
: "${DB:?DB env var required (ex.: DB=imopush)}"
export PGHOST="${PGHOST:-h-postgres}"
export PGUSER="${PGUSER:-postgres}"

upper=$(echo "$DB" | tr '[:lower:]' '[:upper:]')
pw_var="${upper}_PASSWORD"
pw=$(printenv "$pw_var") || true
if [ -z "$pw" ]; then
  echo "ERRO: ${pw_var} não definida (deve vir de secrets/${DB}.env)" >&2
  exit 1
fi

PGDATABASE=postgres psql -v ON_ERROR_STOP=1 <<EOSQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB}') THEN
    EXECUTE format('CREATE ROLE %I WITH LOGIN PASSWORD %L', '${DB}', '${pw}');
  END IF;
END
\$\$;
SELECT 'CREATE DATABASE "${DB}" OWNER "${DB}"'
  WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB}')\gexec
EOSQL

echo "bootstrap OK: db=${DB} role=${DB}"

#!/bin/sh
# h-restic entrypoint: cron daemon OR ad-hoc job dispatcher.
# Usage: entrypoint.sh [cron|backup|check|forget]
# Default: cron — init repo se preciso, depois exec supercronic.
set -eu

notify() {
  # Push deadman ao Gatus (ops_restic-backup / -check / -forget endpoints).
  curl -fsS -m 10 --retry 3 -X POST \
    "http://h-gatus:8080/api/v1/endpoints/ops_restic-$1/external?token=$GATUS_TOKEN&success=$2" \
    >/dev/null || true
}

run() {
  job=$1; shift
  if "$@"; then notify "$job" true
  else notify "$job" false; exit 1
  fi
}

case "${1:-cron}" in
  cron)
    # Init idempotente: skip se repo já existe (restic snapshots OK).
    restic snapshots >/dev/null 2>&1 || restic init
    exec supercronic /etc/crontab
    ;;
  backup)
    run backup restic backup /source --tag scheduled --exclude-file=/etc/restic/excludes
    ;;
  check)
    run check restic check --read-data-subset=5%
    ;;
  forget)
    run forget restic forget --tag scheduled \
      --keep-daily 7 --keep-weekly 4 --keep-monthly 12 --keep-yearly 2 --prune
    ;;
  *)
    echo "Usage: $0 {cron|backup|check|forget}" >&2
    exit 1
    ;;
esac

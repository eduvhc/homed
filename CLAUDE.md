# homed

Self-hosted home server stack — declarative Docker Compose, 18 services,
SOPS-encrypted secrets, GitOps via doco-cd, infra via OpenTofu.

## Standard

Project-local skill `modular-compose` (em `.claude/skills/`) define o standard
de arquitectura compose. Auto-load quando tocas qualquer compose file.

Reads obrigatórios antes de mudar arquitectura:
- `docs/compose-standard.md` — 13 regras (LoC cap, fragments, anchors, shell)
- `README.md` — onboarding humano + bring-up runbook
- `Taskfile.yaml` — todas as operações (decrypt, up, restic-*, tofu-*)

## Layout

`compose/stacks/h-<svc>/` (flat, sem categorias) — entry `compose.yaml` +
opcionais `runtime.yaml` / `init.yaml` / `backups.yaml` / `compose.bootstrap.yaml`.
Root `compose/compose.yaml` agrega via `include:`.

## Secrets

SOPS in-place em `secrets/*.env` (sops 3.12, age recipient em `.sops.yaml`).
**Nunca editar encrypted files directly** — usar `task decrypt|lock|edit|encrypt|rotate`.

## Validação obrigatória

`task validate` após qualquer mudança — `docker compose config -q` clean antes de commit.

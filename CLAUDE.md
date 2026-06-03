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

## NUNCA fix-and-pray (regra dura, não-negociável)

Fix-and-pray = aplicar fix sem perceber a causa-raiz, ver se desbloqueia,
descobrir nova falha, aplicar novo fix sem perceber, repetir. Estritamente
proibido. Sintomas:

- Cadeia de commits `fix(x): try Y / fix(x): actually try Z / fix(x): hmm now W`
- "Vamos lá tentar isto" sem source-citation
- Esperança como mecanismo de validação ("deve funcionar")

**Antes de QUALQUER fix (não só bugs — qualquer mudança), pesquisar:**

1. **Service reference (source code do upstream)** — `~/projects/references/<svc>/`
   ou `git clone` se não existir. Cita ficheiro:linha que justifica o fix.
2. **Web** via WebFetch/WebSearch — docs oficiais, changelogs, issues GitHub.
   Patterns/answers de blogs ficam stale em ~3 meses; trata como pista, não verdade.
3. **Compara**: se source e web divergem, source ganha (web pode estar outdated).

Memória, intuição, "lembro-me que era assim" — **NÃO são fontes**. Verifica
sempre antes de tocar em código.

**Sequência obrigatória**:

1. Pesquisa (1) + (2) acima → cita evidência.
2. **Propõe UMA solução vetted** — explicita o que vai ser feito + porquê +
   citação ao source. Se há ambiguidade entre 2 caminhos, escolhe baseado em
   evidência, não preferência.
3. **Só então edita.**

A excepção: typos óbvios sem ambiguidade (path errado typo, missing newline).
Marca explicitamente como "trivial — sem source-check" no commit.

Se durante a investigação se descobre que a abordagem inicial estava errada,
**reverte e recomeça**. Não acumular hot-fixes em cima do erro original. Esse
é o anti-pattern: cada fix expõe outra camada porque o diagnóstico inicial
estava errado.

Quando reconheceres-te em modo fix-and-pray (>2 commits seguidos a tentar a
mesma área), **pára**. Dispatch um sub-agent dedicado a source-investigation.
Aceita pausa de 5-10 min em troca de 1 solução vetted.

Origem: sessão 2026-06-03 — debug de Forgejo OIDC + rename. Acumulei 8 commits
de hot-fix antes do user me apanhar e forçar source-verify. O 9º commit
(source-verified) resolveu o problema; os 8 anteriores eram esforço
desperdiçado em direcções erradas.

# Disaster Recovery — homed

> Runbook para recuperar o homelab de cenários de falha discretos. Documenta
> *como* recuperar, *de onde* vêm os ingredientes, e *quanto tempo* esperar.
>
> Single-operator (eduvhc). Sem on-call externo. Sem replicação síncrona.

## 1. Scope e assumptions

**In scope**: recuperação do stack compose, secrets, infra Cloudflare, dados
em volumes (backups restic). Cold-start de máquina nova (operador ou servidor).

**Out of scope**: HA dual-host (single Beelink por design), zero-downtime
deploys, RPO < 24h em volumes não-críticos.

**Assumptions**:

- Bitwarden Personal (`bw` CLI + master password) está acessível — é o root of trust.
- GitHub `eduvhc/homed` continua publicamente acessível (mirror upstream do Forgejo).
- Cloudflare account `iedora.com` mantido (DNS + Tunnel + R2 bucket).
- Pelo menos um operador (Mac ou Win/WSL2) consegue instalar mise + bws + tofu.

## 2. Threat model

Cenários priorizados por probabilidade × impacto:

| Cenário | Prob | Impacto | Coberto por |
|---|---|---|---|
| Mac do operador morre / é roubado | M | Médio | Bitwarden Personal → re-bootstrap operator |
| Beelink falha (SSD, PSU) | M | Alto | restic restore + provision novo host |
| fat-finger: `docker volume rm` errado | M | Alto-baixo | restic snapshot anterior |
| Cloudflare account compromise/lock | B | Crítico | Nova account + tofu re-apply + restore |
| Ransomware do Beelink | B | Crítico | restic repo append-only (R2 token write-only) |
| R2 region loss / Cloudflare R2 outage | MB | Crítico | **Gap — único offsite. Ver §9 (anti-patterns).** |
| age key perdida (Bitwarden lockout) | MB | Catastrófico | Bitwarden Emergency Access + paper backup |
| GitHub upstream taken down | MB | Médio | Forgejo já tem clone — re-host noutro lado |

## 3. Tier classification + RTO/RPO

RPO = quanto de dados é aceitável perder. RTO = tempo para restaurar.

| Serviço | Tier | RPO | RTO | Backup mechanism | Restore mechanism |
|---|---|---|---|---|---|
| h-postgres (forgejo+authelia+apps) | T1 | 24h | 1h | `pg_dumpall` diário → /data → restic | restic restore + `psql -f dump.sql` |
| h-forgejo (repos + DB) | T1 | 24h | 1h | DB no postgres + repos em volume → restic | restic restore + mirror fallback do GitHub |
| h-auth (Authelia config + sessions) | T1 | 24h | 30min | config em git, sessions volátil em valkey | re-clone repo, sessions perdem-se (re-login) |
| h-restic (engine de backups) | T1 | n/a | 30min | é o engine — não se faz backup a si | docker compose up + `task restic -- init` |
| h-doco-cd | T2 | 7d | 30min | config em git | redeploy via compose |
| h-cloudflared | T2 | 7d | 30min | token via tofu output | `task tofu:sync-secrets` |
| h-proxy (caddy) | T2 | 7d | 30min | config em git, certs auto-emite | redeploy; Let's Encrypt re-emite |
| h-adguard (filtros + logs) | T2 | 7d | 1h | config em volume → restic | restic restore volume |
| h-lidarr/prowlarr/qbittorrent | T3 | 30d | best-effort | config em volume → restic | restic restore OU re-config manual |
| h-navidrome (state) | T3 | 30d | best-effort | metadata SQLite → restic | restic restore OU re-scan |
| h-yt-dlp (downloads) | T3 | ∞ | best-effort | nenhum — downloads voláteis por design | re-download do youtube |
| h-dashboard/h-gatus/h-glances | T3 | ∞ | best-effort | config em git | redeploy |

**Boot-time critical path** (re-construir do zero): tofu (DNS+tunnel) → provision (Beelink+mise) → secrets bootstrap (age key) → SOPS decrypt → forgejo (auto-clone do GitHub mirror) → doco-cd → restantes via doco-cd reconciliation → restic restore volumes T1.

## 4. Backup strategy — 3-2-1-1-0

Modelo: 3 cópias / 2 media / 1 offsite / 1 immutable / 0 erros silenciosos.

| Critério | Estado | Notas |
|---|---|---|
| **3 cópias** | ✓ | Live (Beelink volumes) + restic local cache (Beelink) + restic R2 |
| **2 media** | ⚠️ Parcial | Beelink SSD + R2 cloud. Sem segunda media local distinta. |
| **1 offsite** | ✓ | R2 (US/EU edge) |
| **1 immutable** | ⚠️ Parcial | Restic é append-only se token só tem Write+Read sem Delete. **Validar tokens R2 actuais.** |
| **0 erros silenciosos** | ❌ | Sem drill automatizado de restore. `restic check` corre semanalmente (gatus monitora). Ver §8. |

**Gap conhecido**: R2 é único offsite. Se Cloudflare loses account ou banir, perdemos backup remoto. Mitigação futura: secondary off-site (B2 / Hetzner Storage Box). Tracked em backlog.

## 5. Bootstrap secrets envelope

**Root of trust**: Bitwarden Personal vault (master password memorizada pelo operador).

```
Bitwarden Personal vault (bw)
  └─ BWS_ACCESS_TOKEN (note) ──┐
                               ↓
                  bws CLI → projecto homed
                               ↓
              HOMED_BWS_PROJECT_ID
              CLOUDFLARE_API_TOKEN
              HOMED_TOFU_ENCRYPTION
              HOMED_AGE_KEY
              R2_STATE_ACCESS_KEY
              R2_STATE_SECRET_KEY
                               ↓
                  age key file (~/.config/sops/age/keys.txt)
                               ↓
                  SOPS decrypt secrets/*.env
                               ↓
                  stack arranca
```

**Cadeia de dependência** (sem atalhos):
1. Memória → Bitwarden master password
2. Bitwarden vault → BWS_ACCESS_TOKEN
3. bws → todos os outros secrets do projecto homed
4. age key → SOPS decrypt
5. Tudo o resto

**Recovery deste root** se Bitwarden ficar inacessível:

- ⚠️ **TODO operator**: configurar **Bitwarden Emergency Access** (Premium feature — relativo de confiança aprova após N dias)
- ⚠️ **TODO operator**: imprimir **Bitwarden Emergency Recovery Sheet** + backup codes 2FA, guardar em local físico seguro
- ⚠️ **TODO operator**: paper backup do `HOMED_AGE_KEY` em segunda localização (sem isto, perder Bitwarden = perder todos os secrets encriptados em git)

## 6. Cold-start runbooks (por cenário)

### 6.1 Mac do operador perdido / roubado

**RTO**: 30 min. **RPO**: 0 (nada vive só no Mac).

```bash
# Mac novo (ou Win/WSL2, ou Linux fresh)
# 1. Bitwarden Personal — instala + login
brew install --cask bitwarden       # ou bw CLI: brew install bitwarden-cli
bw login eduardoferdcarvalho@gmail.com
bw unlock                            # master password

# 2. Recuperar BWS_ACCESS_TOKEN do vault
export BWS_ACCESS_TOKEN=$(bw get notes "homed BWS access token" | sed -n 's/^token: //p')
export HOMED_BWS_PROJECT_ID=<UUID guardado em notes do mesmo item>

# 3. mise + tools + repo
curl -fsSL https://mise.run | sh
git clone https://github.com/eduvhc/homed ~/homed && cd ~/homed
mise trust && mise install

# 4. Bootstrap age key + secrets
task secrets:bootstrap-age-key
task secrets:decrypt                # validar que decifra OK

# 5. ssh keys (não estão em bws — ver ~/.ssh em backup pessoal noutro lado)
# (TODO operator: documentar onde vivem as ssh keys do operador — Time Machine? 1Password?)

# 6. Done — stack continua a correr no Beelink, nada foi tocado.
```

### 6.2 Beelink morto, R2 intacto

**RTO**: 2-4h (Debian install + provision + restore). **RPO**: ≤24h (último restic snapshot).

```bash
# 1. Hardware novo: USB Debian 12 / Ubuntu 24.04 net-install, criar user eduvhc, ssh key

# 2. Operator (Mac/WSL2) — já tem tudo
cd ~/homed
# 2a. ajustar IP em ansible/inventory.yml para o novo host
# 2b. correr provision
task provision HOST=beelink
# (instala mise + tools, docker, tailscale, copia age key, configura UFW)

# 3. Cold-clone do upstream (forge.iedora.com ainda não existe)
ssh -l eduvhc <novo-ip>
git clone https://github.com/eduvhc/homed ~/homed && cd ~/homed
mise trust && mise install

# 4. Trazer o stack
task up PROFILE=bootstrap            # decrypt + builds + compose com profile bootstrap
# Tudo arranca limpo. Forgejo init via bootstrap. doco-cd ainda aponta a forge local.

# 5. Restore dos volumes T1 do restic
task restic -- snapshots             # lista
task restic:restore SNAP=latest TARGET=/data
# (TODO documentar exact volumes paths — ver §7 per-service)

# 6. Validar
curl -fsI https://auth.iedora.com    # 200 esperado
curl -fsI https://forge.iedora.com   # 200 esperado
docker compose -f compose/compose.yaml ps  # tudo healthy
```

### 6.3 Beelink morto, R2 intacto, repo Forgejo perdido

Idêntico a 6.2, plus passo extra: doco-cd não consegue puxar do Forgejo local (ainda não existe).

- O bootstrap inicial puxa do `UPSTREAM_REPO` (GitHub) directamente — `config.sh` cria o repo no Forgejo como mirror do GitHub. Forgejo migra automaticamente.
- Após Forgejo migrate completo, doco-cd reconcilia normalmente.

Confirma `~/homed/compose/stacks/h-forgejo/bootstrap/steps/config.sh:42` — `mirror:true, mirror_interval:"10m"`. Funciona out-of-the-box.

### 6.4 Cloudflare account compromise / lock

**RTO**: 1-2 dias (esperar resposta CF support OU criar nova account). **RPO**: 0 (config em git+tofu, dados em backup local).

1. Nova CF account, transferir domínio `iedora.com` (ou usar domínio temporário)
2. Criar novo CLOUDFLARE_API_TOKEN com permissões correctas
3. Criar novo R2 bucket `homed-backups` (novo cloud-side)
4. Atualizar bws: novos `R2_STATE_*` + `CLOUDFLARE_API_TOKEN`
5. `task tofu CMD='init -migrate-state'` — apontar para novo R2
6. `task tofu:apply` — recria DNS + tunnel
7. Restore restic do backup local Beelink (cópia 2 da 3-2-1) → re-upload para novo R2
8. Stack continua funcional

**Gap real**: se R2 é a **única** cópia offsite e perdemos a account, perdemos backups remotos. Cópia local no Beelink restic-cache cobre — mas se Beelink também down, é game over para dados T1 anteriores ao último snapshot que tivermos noutro lado. Ver §9.

### 6.5 Full nuke (Mac + Beelink + R2 perdidos)

**RTO**: 1-2 semanas. **RPO**: dados T1 perdidos se não houver backup offsite secundário.

1. Bitwarden Personal recovery → BWS token
2. Hardware novo (Mac + Beelink)
3. Cold-start 6.1 + 6.2 + 6.4 sequencialmente
4. **Dados em volumes**: perdidos. Aceitar e re-popular do que sobreviver (Forgejo: pull do GitHub mirror; Postgres: vazio; Authelia: re-config; media: irrecuperável se não houver backup pessoal noutro lado).

Este cenário é a razão para considerar **secondary offsite** no backlog.

## 7. Per-service restore (corruption parcial)

Cenário: stack live, mas um serviço/DB corrupted ou dados acidentalmente apagados.

### Postgres database X corrupted

```bash
# Tipicamente os dumps são em /data/h-postgres/dumps/<db>-YYYYMMDD.sql.gz
docker compose -f compose/compose.yaml exec h-postgres bash -c '
  dropdb -U postgres <db>
  createdb -U postgres <db>
  gunzip -c /data/dumps/<db>-<date>.sql.gz | psql -U postgres <db>
'
# Re-start dependentes (forgejo/authelia/etc.)
docker compose -f compose/compose.yaml restart h-forgejo h-auth
```

### Authelia config corrompido

`compose/stacks/h-auth/config/` está em git → `git checkout HEAD -- compose/stacks/h-auth/config/`. Restart h-auth.

### Forgejo repos corrupted

Para o repo `homed` específico: tem mirror do GitHub, basta deixar `mirror_interval` re-sync. Para outros repos: restic restore do volume `h-forgejo-data`.

### Volume X completamente apagado

```bash
task restic -- snapshots --tag h-<svc> | head -5
task restic:restore SNAP=<id> TARGET=/data/h-<svc>
docker compose -f compose/compose.yaml up -d h-<svc>
```

## 8. Verification — drill schedule

| Cadência | O quê | Como | Estado |
|---|---|---|---|
| Diário | restic backup health | `gatus` monitora `h-restic check` | ✓ active |
| Semanal | `restic check` repo integrity | Cron container `h-restic-check` | ✓ active |
| Mensal | `restic check --read-data-subset 10%` | TODO: adicionar cron | ❌ não configurado |
| Trimestral | **Full restore drill** para volume tmp + checksum vs canary | TODO: scripted via `task` ou cron | ❌ não configurado |
| Anual | Tabletop completo (sequência 6.5) — sem executar, só percorrer | TODO: agendar | ❌ não configurado |

**Verdade incómoda**: até o restore mensal/trimestral ser scripted e correr automaticamente, os backups são **Schrödinger backups** — válidos até alguém precisar. servercrate dixit: *"a check script that fails silently is worse than no check."*

## 9. Anti-patterns / gotchas conhecidos

1. **R2 é o único offsite** — viola 3-2-1 estritamente (precisa de 1 cópia em media distinta + offsite). Para resolver: secondary backup destination (B2, Hetzner Storage Box, ou disco USB rotativo). Sem isso, account loss da Cloudflare = data loss permanente de T1.

2. **age key custody loop** — bws contém `HOMED_AGE_KEY`. Decryptar `secrets/h-restic.env` (que tem R2 keys do restic) requer age key. Se Bitwarden ficar inacessível, perdemos acesso a TODOS os secrets encriptados em git. Mitigação: paper backup do age key conteúdo em local físico distinto.

3. **Forgejo↔doco-cd↔GitHub mirror loop** — doco-cd puxa do Forgejo local. Se Forgejo down, deploys param. Cold-start cobre via `UPSTREAM_REPO=https://github.com/eduvhc/homed.git` que faz Forgejo re-clone do GitHub. Não testado em prod desde commit `78cb9cb`.

4. **Tofu state em R2 + R2 keys em bws** — circular: para correr tofu precisas de R2 keys; para R2 keys precisas de bws; para bws precisas de Bitwarden Personal. Mitigação: cadeia inteira ancorada no master password do Bitwarden (ver §5). Não dá para encurtar sem second-source dos secrets.

5. **Sem restore drill automatizado** — backups assumidos OK até alguém precisar. Ver §8.

6. **Single operator, sem on-call** — se eu fico incomunicável e o homelab cai, ninguém recupera. Mitigação parcial: Bitwarden Emergency Access para relativo + este doc em git público. Sem on-call backup planeado.

7. **SSH keys do operador fora do scope deste doc** — vivem em `~/.ssh` no Mac, **não estão em bws**. Recuperar Mac perdido implica regenerar keys + actualizar `~/.ssh/authorized_keys` no Beelink. TODO operator: documentar onde vivem as ssh keys (Time Machine? cópia em segundo dispositivo?).

8. **Não testado**: cenários 6.4 e 6.5 são teóricos. Cenário 6.2 foi parcialmente exercitado nesta sessão (2026-06-03 — provision em Ubuntu validado, full restore não).

## 10. Operator info

- **Operador principal**: eduvhc (`eduardoferdcarvalho@gmail.com`)
- **Bitwarden vault**: pessoal, conta com 2FA (TOTP). Master password memorizada.
- **Cloudflare account**: pessoal, mesma email. 2FA ativo.
- **GitHub upstream mirror**: `github.com/eduvhc/homed` (público)
- **Forgejo self-hosted**: `forge.iedora.com` (post-recovery)
- **Backup do master password Bitwarden**: ⚠️ TODO — papel ou Bitwarden Emergency Sheet em local físico seguro

---

**Updates a este doc**: cada sessão de hardening / DR drill deve actualizar §8 (drill schedule), §9 (gotchas — adicionar/remover), e a data abaixo.

**Última revisão**: 2026-06-03 (criação inicial; baseado em research de homelab DR corpus + estado real da stack pós-`cf818d7`).

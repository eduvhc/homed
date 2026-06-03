#!/usr/bin/env bash
# bootstrap.sh — single-command setup from fresh server (Debian 12+ / Ubuntu 22.04+).
#
# UX:
#   ssh user@server
#   git clone https://github.com/eduvhc/homed && cd homed
#   ./bootstrap.sh
#   [prompt: cola age key + Ctrl-D]
#   [prompt: sudo password]
#   → stack up em ~5min
#
# Idempotente — re-rodar é seguro (skipa o que já está feito).
# CI-friendly:
#   HOMED_AGE_KEY=<conteúdo> ANSIBLE_BECOME_PASS=<pw> ./bootstrap.sh
set -euo pipefail
cd "$(dirname "$0")"

log() { printf '\033[1;34m→\033[0m %s\n' "$*" >&2; }
ok()  { printf '\033[1;32m✓\033[0m %s\n' "$*" >&2; }

# ── 1. distro sanity ──────────────────────────────────────────────────────────
if [ -f /etc/os-release ]; then . /etc/os-release; fi
case "${ID:-}" in
  debian|ubuntu) ok "distro: $ID $VERSION_ID" ;;
  *) echo "✗ Suporte: Debian 12+ ou Ubuntu 22.04+ (actual: ${ID:-?})" >&2; exit 1 ;;
esac

# ── 2. mise (CLI tools pinning, cross-OS) ─────────────────────────────────────
if [ ! -x "$HOME/.local/bin/mise" ]; then
  log "instalando mise..."
  curl -fsSL https://mise.run | sh
fi
export PATH="$HOME/.local/bin:$PATH"
mise trust >/dev/null 2>&1 || true
log "mise install (tools pinned em .mise.toml)..."
mise install

# ── 3. ansible (não está em .mise.toml — pipx complexity) ─────────────────────
if ! command -v ansible-playbook >/dev/null 2>&1; then
  log "ansible em falta — instalando via apt (sudo)..."
  sudo apt-get update -qq && sudo apt-get install -y ansible
fi

# ── 4. age key via task (env → bws → prompt) ──────────────────────────────────
log "age key bootstrap..."
mise exec -- task secrets:bootstrap-age-key

# ── 5. provision (docker + ufw + tailscale + ~/.bashrc env) ───────────────────
log "provision sistema (Ansible)..."
mise exec -- task provision HOST=localhost

# ── 6. compose stack ──────────────────────────────────────────────────────────
log "stack up (profile bootstrap)..."
mise exec -- task up PROFILE=bootstrap

ok "Bootstrap completo. Próximo:"
echo "  - 'sudo tailscale up' (se quiseres Tailscale)"
echo "  - 'docker compose -f compose/compose.yaml ps' (verificar healthchecks)"
echo "  - 'newgrp docker' OU re-login para o grupo docker ficar activo"

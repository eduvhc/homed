# forgejo-bootstrap — multiplexa provisioning steps via BOOTSTRAP_STEP env.
#
# Steps:
#   admin   — cria 1º admin via `forgejo admin user create` (CLI; sem REST chicken-egg)
#   oidc    — regista Authelia OAuth source via `forgejo admin auth add-oauth` (CLI)
#   config  — REST: importa repo + cria PAT + registra webhook → /shared/
#
# Base: forgejo:15-rootless (CLI access ao binário forgejo) + curl/jq (steps REST).
# UID 1000:1000 (git) — mesmo do runtime h-forgejo, partilha h-forgejo-data volume.

FROM codeberg.org/forgejo/forgejo:15-rootless
USER root
RUN apk add --no-cache curl jq
COPY --chmod=755 bootstrap.sh /usr/local/bin/bootstrap.sh
COPY --chmod=755 steps/ /usr/local/bin/steps/
USER 1000:1000
ENTRYPOINT ["/usr/local/bin/bootstrap.sh"]

# forgejo-config-bootstrap — init container declarativo que provisiona state
# do repo no Forgejo (PAT do agent + webhook do doco-cd) via API REST.
#
# Idempotente: detecta state existente (GET) antes de criar (POST). Grava as
# credenciais geradas num volume partilhado lido pelo h-doco-cd.
FROM alpine:3.20
RUN apk add --no-cache curl jq
COPY bootstrap.sh /usr/local/bin/bootstrap.sh
RUN chmod +x /usr/local/bin/bootstrap.sh
ENTRYPOINT ["/usr/local/bin/bootstrap.sh"]

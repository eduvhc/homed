FROM alpine:3.20

# Tools necessárias para os hooks: git (clone/pull), docker CLI + compose
# (build + restart), curl (heartbeats Gatus), bash (scripts).
# NOTA: docker-cli-compose do Alpine 3.20 é v2.27 — não suporta o merge
# de networks que o nosso compose.yaml usa. Instalamos compose v2.31+
# do binário oficial em vez disso.
RUN apk add --no-cache \
      docker-cli \
      git openssh-client \
      ca-certificates curl bash tini \
      go-task \
    && rm -rf /var/cache/apk/*

# Compose plugin v2.31.0 do binário oficial (Alpine 3.20 só tem 2.27).
RUN mkdir -p /usr/local/libexec/docker/cli-plugins \
    && ARCH=$(uname -m) \
    && curl -fsSL "https://github.com/docker/compose/releases/download/v2.31.0/docker-compose-linux-${ARCH}" \
         -o /usr/local/libexec/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/libexec/docker/cli-plugins/docker-compose

# Binário oficial do webhook (não há imagem oficial; copiamos do build upstream)
COPY --from=ghcr.io/thecatlady/webhook:2.8.2 /usr/local/bin/webhook /usr/local/bin/webhook

# Workdir partilhado: aqui vão estar os repos clonados (bind-mount).
RUN mkdir -p /workspace
WORKDIR /workspace

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/webhook"]
CMD ["-hooks", "/etc/webhook/hooks.yaml", "-verbose", "-port", "9000", "-template"]

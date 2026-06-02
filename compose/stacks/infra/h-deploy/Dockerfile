FROM alpine:3.20

# Tools necessárias para os hooks: git (clone/pull), docker CLI + compose
# (build + restart), curl (heartbeats Gatus), bash (scripts).
RUN apk add --no-cache \
      docker-cli docker-cli-compose \
      git openssh-client \
      ca-certificates curl bash tini \
      go-task \
    && rm -rf /var/cache/apk/*

# Binário oficial do webhook (não há imagem oficial; copiamos do build upstream)
COPY --from=ghcr.io/thecatlady/webhook:2.8.2 /usr/local/bin/webhook /usr/local/bin/webhook

# Workdir partilhado: aqui vão estar os repos clonados (bind-mount).
RUN mkdir -p /workspace
WORKDIR /workspace

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/webhook"]
CMD ["-hooks", "/etc/webhook/hooks.yaml", "-verbose", "-port", "9000", "-template"]

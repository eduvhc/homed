FROM alpine:3.20

# Tools:
#   docker-cli       — chamadas ao daemon (compose v2.31 instalado via binário)
#   git              — usado pelo módulo ansible.builtin.git
#   ansible-core     — orquestrador declarativo (substitui scripts shell)
#   py3-docker       — backend Python para os módulos community.docker.*
#   ca-certificates  — TLS para curl / git
#   tini             — init PID 1
RUN apk add --no-cache \
      docker-cli \
      git openssh-client \
      ansible-core py3-pip py3-requests \
      ca-certificates curl tini \
    && pip install --break-system-packages --no-cache-dir docker \
    && rm -rf /var/cache/apk/*

# Compose plugin v2.31.0 (Alpine 3.20 só tem 2.27; precisamos do merge de
# networks/volumes em include: que só está estável a partir de 2.30+).
RUN mkdir -p /usr/local/libexec/docker/cli-plugins \
    && ARCH=$(uname -m) \
    && curl -fsSL "https://github.com/docker/compose/releases/download/v2.31.0/docker-compose-linux-${ARCH}" \
         -o /usr/local/libexec/docker/cli-plugins/docker-compose \
    && chmod +x /usr/local/libexec/docker/cli-plugins/docker-compose

# Webhook binary (não há imagem oficial — copia do build comunitário pinned)
COPY --from=ghcr.io/thecatlady/webhook:2.8.2 /usr/local/bin/webhook /usr/local/bin/webhook

# Ansible collections necessárias: módulos docker_image_build, docker_compose_v2
RUN ansible-galaxy collection install community.docker:>=3.10 --collections-path /usr/share/ansible/collections

WORKDIR /workspace
RUN mkdir -p /workspace

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/webhook"]
CMD ["-hooks", "/etc/webhook/hooks.yaml", "-verbose", "-port", "9000", "-template"]

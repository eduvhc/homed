# DNS records: subdomínios *.iedora.com → tunnel.
# Cada CNAME aponta para <tunnel_id>.cfargotunnel.com; o cloudflared local
# resolve internamente para o container correto via ingress rules.

locals {
  tunnel_hostname = "${cloudflare_zero_trust_tunnel_cloudflared.homed.id}.cfargotunnel.com"

  # Subdomínios servidos pelo homed. Adicionar entradas aqui à medida que
  # novos serviços públicos são criados.
  subdomains = toset([
    "auth",
    "adguard",
    "deploy",
    "gatus",
    "home",
    "musica",
    "lidarr",
    "prowlarr",
    "qb",
    "whoami",
  ])
}

resource "cloudflare_dns_record" "service" {
  for_each = local.subdomains

  zone_id = var.cf_zone_id
  name    = "${each.value}.${var.domain}"
  type    = "CNAME"
  content = local.tunnel_hostname
  proxied = true
  ttl     = 1 # 1 = "Automatic" quando proxied
  comment = "homed · ${each.value}"
}

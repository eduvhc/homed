# Cloudflare Zero Trust Tunnel — endpoint ingress para o homed.
# Tofu cria o tunnel + secret; o container `h-cloudflared` (futuro) consome
# o token via env_file e mantém as ingress rules em compose/.

resource "random_password" "tunnel_secret" {
  length  = 64
  special = false
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "homed" {
  account_id    = var.cf_account_id
  name          = var.tunnel_name
  config_src    = "local" # ingress rules vivem no Beelink (config.yml do cloudflared)
  tunnel_secret = base64encode(random_password.tunnel_secret.result)
}

# Token de autenticação (data source separado no provider v5)
data "cloudflare_zero_trust_tunnel_cloudflared_token" "homed" {
  account_id = var.cf_account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.homed.id
}

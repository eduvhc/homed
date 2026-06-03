# Outputs consumidos por `task tofu:sync-secrets`:
# escreve cada output sensível para o secret correto em ../secrets/

output "tunnel_id" {
  description = "ID do Cloudflare Tunnel"
  value       = cloudflare_zero_trust_tunnel_cloudflared.homed.id
}

output "tunnel_token" {
  description = "Token para o cloudflared local autenticar — vai para secrets/h-cloudflared.env"
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.homed.token
  sensitive   = true
}

output "tunnel_hostname" {
  description = "Hostname interno do tunnel (target dos CNAMEs)"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.homed.id}.cfargotunnel.com"
}

output "r2_bucket_name" {
  description = "Nome do bucket R2 para backups"
  value       = cloudflare_r2_bucket.backups.name
}

output "r2_endpoint" {
  description = "Endpoint S3-compatível do R2 — para RESTIC_REPOSITORY"
  value       = "s3:https://${var.cf_account_id}.r2.cloudflarestorage.com/${cloudflare_r2_bucket.backups.name}"
}

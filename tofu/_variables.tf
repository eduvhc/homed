variable "cf_api_token" {
  description = "Cloudflare API token (scope: Account R2 Edit, Zone DNS Edit, Account Cloudflare Tunnel Edit)"
  type        = string
  sensitive   = true
}

variable "cf_account_id" {
  description = "Cloudflare account ID (Dashboard → conta → sidebar)"
  type        = string
}

variable "cf_zone_id" {
  description = "Cloudflare zone ID para iedora.com"
  type        = string
}

variable "encryption_passphrase" {
  description = "Passphrase para state encryption (Tofu 1.10 nativo). Não persistir em plaintext."
  type        = string
  sensitive   = true
}

variable "domain" {
  description = "Domínio raiz"
  type        = string
  default     = "iedora.com"
}

variable "tunnel_name" {
  description = "Nome do Cloudflare Tunnel a criar"
  type        = string
  default     = "homed"
}

variable "r2_bucket_name" {
  description = "Nome do bucket R2 para backups Restic"
  type        = string
  default     = "homed-backups"
}

variable "r2_location" {
  description = "Localização do bucket R2 (EU para latência menor + GDPR)"
  type        = string
  default     = "eeur" # Eastern Europe; alternativas: "weur", "enam", "wnam", "apac"
}

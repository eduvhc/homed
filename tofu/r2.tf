resource "cloudflare_r2_bucket" "backups" {
  account_id    = var.cf_account_id
  name          = var.r2_bucket_name
  location      = var.r2_location
  storage_class = "Standard"
}

# Lifecycle: Restic gere retention internamente via `forget --prune`.
# Como segurança extra, R2 também aplica expiry — versão de fallback caso
# o restic forget falhe. Janela generosa (180 dias) para não conflitar com
# a política mensal/anual do restic.
resource "cloudflare_r2_bucket_lifecycle" "backups" {
  account_id  = var.cf_account_id
  bucket_name = cloudflare_r2_bucket.backups.name

  rules = [
    {
      id      = "expire-stale-objects"
      enabled = true
      conditions = {
        prefix = ""
      }
      delete_objects_transition = {
        condition = {
          type    = "Age"
          max_age = 180 * 24 * 60 * 60 # 180 dias em segundos
        }
      }
      # Limpar uploads multipart inacabados (não há razão para deixar tail-end de uploads partidos)
      abort_multipart_uploads_transition = {
        condition = {
          type    = "Age"
          max_age = 7 * 24 * 60 * 60
        }
      }
    }
  ]
}

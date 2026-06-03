# Remote state em R2 com lock nativo (OpenTofu 1.10+ use_lockfile via S3
# conditional writes — sem DynamoDB).
#
# State é encriptado em _encryption.tf ANTES do upload, logo R2 vê só ciphertext.
# Bucket = mesmo do restic (homed-backups), prefix tofu/. Acesso operator-only.
#
# Endpoints URL é dinâmico (CF account ID vem da API) — passado via
# `-backend-config="endpoints={s3=...}"` no `tofu init` (ver .taskfiles/tofu.yaml).
#
# Pré-req operator (one-time): R2_STATE_ACCESS_KEY + R2_STATE_SECRET_KEY no
# projecto bws (R2 API tokens com Object Read & Write no homed-backups).

terraform {
  backend "s3" {
    bucket = "homed-backups"
    key    = "tofu/homed.tfstate"
    region = "auto"

    use_lockfile = true # nativo R2 (If-None-Match) — sem DynamoDB

    # R2 não tem AWS-style credential validation / region / account verification
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true # R2 checksum differs do AWS S3
  }
}

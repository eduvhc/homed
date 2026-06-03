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

    # R2 path-style addressing (canónico — CF official docs).
    # Virtual-hosted-style flaks contra R2 subdomains em SDK v2.
    use_path_style = true

    # R2 não tem AWS-style credential validation / region / account verification
    # nem EC2 instance metadata endpoint (skip_metadata_api_check para non-AWS hosts).
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_s3_checksum            = true # R2 checksum differs do AWS S3
  }
}

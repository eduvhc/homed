terraform {
  required_version = ">= 1.10"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.19" # 5.19.1 (2026-05-30), pinned ao minor
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9" # 3.9.0
    }
  }
}

provider "cloudflare" {
  api_token = var.cf_api_token
}

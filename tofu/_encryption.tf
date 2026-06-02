# State encryption nativo (OpenTofu 1.10+).
# Passphrase vem de var.encryption_passphrase, injetada por `task tofu-*`
# a partir de tofu/terraform.tfvars.sops. State e plan ficam encriptados
# em disco e são committable ao git sem leak.

terraform {
  encryption {
    key_provider "pbkdf2" "passphrase" {
      passphrase = var.encryption_passphrase
    }

    method "aes_gcm" "default" {
      keys = key_provider.pbkdf2.passphrase
    }

    state {
      method   = method.aes_gcm.default
      enforced = true
    }

    plan {
      method   = method.aes_gcm.default
      enforced = true
    }
  }
}

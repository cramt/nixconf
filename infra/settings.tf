terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}

locals {
  secrets = jsondecode(file(abspath("${path.module}./secrets.json")))
}

provider "cloudflare" {
  api_key = local.secrets.cloudflare_api_key
  email   = local.secrets.email
}

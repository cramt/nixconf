terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    external = {
      source = "hashicorp/external"
    }
  }
  backend "pg" {
    conn_str = "postgres://terraformremotestate:${local.secrets.terraform_remote_state_password}@postgres.${local.secrets.domain}:6432"
  }
}

locals {
  secrets = jsondecode(file(abspath("${path.module}./secrets.json")))
}

provider "cloudflare" {
  api_key = local.secrets.cloudflare_api_key
  email   = local.secrets.email
}

terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
    onepassword = {
      source  = "1Password/onepassword"
      version = "~> 2.1"
    }
    external = {
      source = "hashicorp/external"
    }
  }
  # Configured via PG_CONN_STR env var (use `just tf` to run terraform)
  backend "pg" {}
}

provider "onepassword" {}

data "onepassword_item" "infrastructure" {
  vault = "Homelab"
  title = "Infrastructure"
}

data "onepassword_item" "cloudflare" {
  vault = "Homelab"
  title = "Cloudflare"
}

data "onepassword_item" "terraform_remote" {
  vault = "Homelab"
  title = "TerraformRemoteState"
}

data "onepassword_item" "atproto" {
  vault = "Homelab"
  title = "AtprotoDomain"
}

data "onepassword_item" "email_forwarding" {
  vault = "Homelab"
  title = "EmailForwarding"
}

locals {
  _op = {
    for name, src in {
      infrastructure   = data.onepassword_item.infrastructure
      cloudflare       = data.onepassword_item.cloudflare
      terraform_remote = data.onepassword_item.terraform_remote
      atproto          = data.onepassword_item.atproto
      email_forwarding = data.onepassword_item.email_forwarding
    } :
    name => merge([for s in src.section : { for f in s.field : f.label => f.value }]...)
  }

  secrets = {
    domain                          = local._op.infrastructure["domain"]
    email                           = local._op.infrastructure["email"]
    ip                              = local._op.infrastructure["ip"]
    luna_internal_address           = local._op.infrastructure["lunaInternalAddress"]
    cloudflare_api_key              = local._op.cloudflare["apiKey"]
    terraform_remote_state_password = local._op.terraform_remote["password"]
    atproto_domain_value            = local._op.atproto["value"]
    hannah_atproto_domain_value     = local._op.atproto["hannahValue"]
    email_forwarding                = local._op.email_forwarding
  }
}

provider "cloudflare" {
  api_key = local.secrets.cloudflare_api_key
  email   = local.secrets.email
}

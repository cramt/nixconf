data "cloudflare_accounts" "main" {
  name = "cramt"
}

data "cloudflare_zones" "main" {
  name = local.secrets.domain
}

locals {
  account = element(data.cloudflare_accounts.main.result, 0)
  zone_id = element(data.cloudflare_zones.main.result, 0).id
}

data "cloudflare_zones" "main" {
  name = local.secrets.domain
}

locals {
  zone_id = element(data.cloudflare_zones.main.result, 0).id
}

resource "cloudflare_dns_record" "star" {
  zone_id = local.zone_id
  content = "84.238.86.197"
  name    = "*.${local.secrets.domain}"
  proxied = false
  ttl     = 1
  type    = "A"
}

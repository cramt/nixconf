data "cloudflare_zones" "main" {
  name = "cramt.dk"
}

locals {
  zone_id = element(data.cloudflare_zones.main.result, 0).id
}

resource "cloudflare_dns_record" "star" {
  zone_id = local.zone_id
  content = "84.238.86.197"
  name    = "*.cramt.dk"
  proxied = true
  ttl     = 1
  type    = "A"
}

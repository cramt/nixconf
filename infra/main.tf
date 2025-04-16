data "cloudflare_zones" "main" {
  name = local.secrets.domain
}

locals {
  zone_id = element(data.cloudflare_zones.main.result, 0).id
}

resource "cloudflare_dns_record" "luna" {
  for_each = toset(["jellyfin", "qbit", "foundry-a", "prowlarr", "radarr", "sonarr", "bazarr", "ollama", "cockatrice", "nix-store", "matrix"])
  zone_id  = local.zone_id
  content  = local.secrets.ip
  name     = "${each.key}.${local.secrets.domain}"
  proxied  = true
  ttl      = 1
  type     = "A"
}


resource "cloudflare_dns_record" "luna_raw" {
  for_each = toset(["valheim", "turn", "postgres"])
  zone_id  = local.zone_id
  content  = local.secrets.ip
  name     = "${each.key}.${local.secrets.domain}"
  proxied  = false
  ttl      = 1
  type     = "A"
}

resource "cloudflare_dns_record" "atproto" {
  zone_id = local.zone_id
  content = local.secrets.atproto_domain_value
  name    = "_atproto.${local.secrets.domain}"
  proxied = false
  ttl     = 1
  type    = "TXT"
}

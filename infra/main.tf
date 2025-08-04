resource "cloudflare_dns_record" "luna" {
  for_each = toset(["jellyfin", "jellyseerr", "qbit", "foundry-a", "prowlarr", "radarr", "sonarr", "bazarr", "cockatrice", "nix-store", "matrix"])
  zone_id  = local.zone_id
  content  = local.secrets.ip
  name     = "${each.key}.${local.secrets.domain}"
  proxied  = true
  ttl      = 1
  type     = "A"
}


resource "cloudflare_dns_record" "luna_raw" {
  for_each = toset(["valheim", "bucketapi", "bucket", "turn", "postgres", "ollama"])
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

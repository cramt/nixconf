resource "cloudflare_dns_record" "luna" {
  for_each = toset(["tdarr", "titan-frontend", "open-webui", "jellyfin", "btop", "jellyseerr", "qbit", "foundry-a", "prowlarr", "radarr", "sonarr", "bazarr", "cockatrice", "nix-store", "matrix"])
  zone_id  = local.zone_id
  content  = local.secrets.ip
  name     = "${each.key}.${local.secrets.domain}"
  proxied  = false
  ttl      = 1
  type     = "A"
}


resource "cloudflare_dns_record" "luna_raw" {
  for_each = toset(["valheim", "bucketapi", "bucket", "turn", "postgres", "ollama", "minecraft"])
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

resource "cloudflare_dns_record" "atproto_hannah" {
  zone_id = local.zone_id
  content = local.secrets.hannah_atproto_domain_value
  name    = "_atproto.hannah.${local.secrets.domain}"
  proxied = false
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "github_hannah" {
  zone_id = local.zone_id
  content = "6eebf91a394916de349e9b7bb71a54"
  name    = "_github-pages-challenge-HannahField.hannah.${local.secrets.domain}"
  proxied = false
  ttl     = 1
  type    = "TXT"
}

resource "cloudflare_dns_record" "github_pages_hannah" {
  for_each = toset(["185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"])
  zone_id  = local.zone_id
  content  = each.value
  name     = "hannah.${local.secrets.domain}"
  proxied  = true
  ttl      = 1
  type     = "A"
}

resource "cloudflare_dns_record" "github_pages_hannah_ipv6" {
  for_each = toset(["2606:50c0:8000::153", "2606:50c0:8001::153", "2606:50c0:8002::153", "2606:50c0:8003::153"])
  zone_id  = local.zone_id
  content  = each.value
  name     = "hannah.${local.secrets.domain}"
  proxied  = true
  ttl      = 1
  type     = "AAAA"
}

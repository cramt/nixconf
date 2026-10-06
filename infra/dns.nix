{ lib, ... }:
let
  # for_each over a map keeps the `["<key>"]` addresses the HCL toset() had
  keyed = names: lib.genAttrs names (n: n);

  record = attrs: {
    zone_id = "\${local.zone_id}";
    proxied = false;
    ttl = 1;
  } // attrs;

  lunaHost = record {
    content = "\${var.ip}";
    name = "\${each.key}.\${var.domain}";
    type = "A";
  };
in
{
  resource.cloudflare_dns_record = {
    # vhosts behind luna's reverse proxy
    luna = lunaHost // {
      for_each = keyed [ "tdarr" "yelliv" "open-webui" "jellyfin" "btop" "jellyseerr" "qbit" "foundry-a" "prowlarr" "radarr" "sonarr" "bazarr" "shelfmark" "cockatrice" "metrics" "auth" "t3" "cliproxy" "grafana" ];
    };

    # straight to luna, no proxy in front
    luna_raw = lunaHost // {
      for_each = keyed [ "bucketapi" "bucket" "postgres" "ollama" "minecraft" ];
    };

    atproto = record {
      content = "\${var.atproto}";
      name = "_atproto.\${var.domain}";
      type = "TXT";
    };

    atproto_hannah = record {
      content = "\${var.atproto_hannah}";
      name = "_atproto.hannah.\${var.domain}";
      type = "TXT";
    };

    # Lowercase: Cloudflare stores names lowercased, anything else is a diff on every plan.
    github_hannah = record {
      content = "6eebf91a394916de349e9b7bb71a54";
      name = "_github-pages-challenge-hannahfield.hannah.\${var.domain}";
      type = "TXT";
    };

    github_pages_hannah = record {
      for_each = keyed [ "185.199.108.153" "185.199.109.153" "185.199.110.153" "185.199.111.153" ];
      content = "\${each.value}";
      name = "hannah.\${var.domain}";
      proxied = true;
      type = "A";
    };

    github_pages_hannah_ipv6 = record {
      for_each = keyed [ "2606:50c0:8000::153" "2606:50c0:8001::153" "2606:50c0:8002::153" "2606:50c0:8003::153" ];
      content = "\${each.value}";
      name = "hannah.\${var.domain}";
      proxied = true;
      type = "AAAA";
    };
  };
}

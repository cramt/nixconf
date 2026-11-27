{
  domain = "cramt.dk";
  email = "alex.cramt@gmail.com";
  # MagicDNS zone of the fleet tailnet (Tailscale's own control server, managed
  # in infra/tailscale.nix): <host>.tailaf2719.ts.net
  tailnet_domain = "tailaf2719.ts.net";
  luna_internal_address = "192.168.178.24";
  # luna's addresses on the tailnet. Tailscale keeps them per node key; if luna
  # is ever re-registered, re-read `tailscale ip`.
  luna_tailnet_addresses = ["100.102.220.40" "fd7a:115c:a1e0::62e:dc29"];
  ip = "185.187.144.195";
  # The fleet binary cache (modules/services/hestia-cache.nix). .github/workflows
  # repeats `oci`, since YAML can't read this file.
  hestia = {
    oci = "ghcr.io/cramt/nixconf/hestia";
    host = "luna";
    # hestia keys a cache root by <branch>-<system of the runner that pushed>,
    # and one daemon serves one system, so luna runs one per CI runner system.
    ports = {
      x86_64-linux = 37515;
      aarch64-linux = 37516;
    };
    # main's pushes, and `update`'s, which is what `just update` merges.
    branches = ["main" "update"];
  };
}

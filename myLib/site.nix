{
  domain = "cramt.dk";
  email = "alex.cramt@gmail.com";
  headscale_url = "https://hs.cramt.dk";
  # MagicDNS zone: <host>.ts.cramt.dk
  tailnet_domain = "ts.cramt.dk";
  luna_internal_address = "192.168.178.24";
  # luna's addresses on the tailnet. headscale handed them out first and keeps
  # them per node key; if luna is ever re-registered, re-read `tailscale ip`.
  luna_tailnet_addresses = ["100.64.0.1" "fd7a:115c:a1e0::1"];
  ip = "185.187.144.195";
}

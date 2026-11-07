# Every host running a T3 Code server (myNixOS.services.t3code), and the
# vhost each is reached at. Each server links to all the others
# (modules/services/t3code-fleet.nix), so this is a fleet fact rather than a
# per-host one: a host's own config can't see the others' without making
# every host evaluate every other host.
#
# Upstream sends link credentials only over https (or to loopback/tailnet),
# so a LAN server is linked through luna's caddy: `t3-<host>.<domain>` there
# proxies to `<host>:3773`, and `<port>.t3-<host>.<domain>` to that host's
# preview gateway.
#
# Lives in myLib/ rather than modules/ because import-tree would turn it into a
# flake-parts module; it's a plain helper imported by relative path.
let
  site = import ./site.nix;
in rec {
  # Runs caddy and the passkey portal, so it fronts the others.
  hub = "luna";
  hubAddress = site.luna_internal_address;

  # Host → vhost. The hub's is its own myNixOS.services.t3code.subdomain.
  servers = {
    luna = "t3";
    saturn = "t3-saturn";
    ganymede = "t3-ganymede";
    mars = "t3-mars";
  };
  url = host: "https://${servers.${host}}.${site.domain}";

  # One secret for the fleet: it's each server's pairing code, and what every
  # other server links to it with.
  sharedSecret = "op://Homelab/T3Code/password";

  # Fixed rather than port-selector's, because the hub dials it on other hosts.
  previewGatewayPort = 3774;
}

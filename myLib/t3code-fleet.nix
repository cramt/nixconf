# Every host running a T3 Code server (myNixOS.services.t3code), and the
# vhost each is reached at. Each server links to all the others
# (modules/services/t3code-fleet.nix), so this is a fleet fact rather than a
# per-host one: a host's own config can't see the others' without making
# every host evaluate every other host.
#
# Upstream sends link credentials only over https (or plain http to loopback
# or *.ts.net, which our headscale names aren't), so servers link to each
# other at https://<host>.ts.cramt.dk: each one serves its own tailnet name
# with a real cert (myNixOS.tailnet-https). Browsers off the tailnet still
# come in through luna's caddy: `t3-<host>.<domain>` proxies to `<host>:3773`,
# and `<port>.t3-<host>.<domain>` to that host's preview gateway.
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
  # Where peers link to each other: the tailnet, not the public vhosts.
  url = host: "https://${host}.${site.tailnet_domain}";

  # One secret for the fleet: it's each server's pairing code, and what every
  # other server links to it with.
  sharedSecret = "op://Homelab/T3Code/password";

  # Fixed rather than port-selector's, because the hub dials it on other hosts.
  # Clear of 377x: the desktop app's own server takes the first free port
  # after 3773, so on a host also running the background server it sits on 3774.
  previewGatewayPort = 38774;
}

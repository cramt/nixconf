# Flake-level knobs for luna. Everything else about the host lives in
# configuration.nix / home.nix.
{ ... }:
let
  site = import ../../myLib/site.nix;
in
{
  # 8 cores / 31G, shared with the live services; the daemon's idle scheduling
  # keeps builds from starving jellyfin and friends.
  builder = { maxJobs = 2; };

  # The router forwards 2269 to luna's sshd, so `just deploy luna-remote` works
  # from off the home network.
  wan = { address = site.ip; port = 2269; };
}

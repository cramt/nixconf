# Flake-level knobs for luna. Everything else about the host lives in
# configuration.nix / home.nix.
{ ... }:
{
  # 8 cores / 31G, shared with the live services; the daemon's idle scheduling
  # keeps builds from starving jellyfin and friends.
  builder = { maxJobs = 2; };
}

# Flake-level knobs for saturn. Everything else about the host lives in
# configuration.nix / home.nix.
{ ... }:
{
  # 16 cores / 31G, but it's also the desktop: leave room to keep using it
  # (and parallel builds have OOMed it before).
  builder = { maxJobs = 4; speedFactor = 2; };
}

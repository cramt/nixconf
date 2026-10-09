# Flake-level knobs for ganymede. Everything else about the host lives in
# configuration.nix / home.nix.
{ ... }:
{
  # 7G of RAM: one job at a time or a Rust/C++ build OOMs it.
  builder = { maxJobs = 1; };
}

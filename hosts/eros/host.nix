# Flake-level knobs for eros. Everything else about the host lives in
# configuration.nix / home.nix.
{ inputs, ... }:
{
  # Build from the Raspberry Pi vendor nixpkgs so the kernel and firmware
  # substitute from nixos-raspberrypi.cachix.org instead of being rebuilt.
  nixpkgs = inputs.nixpkgs-rpi;
}

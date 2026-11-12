# Flake-level knobs for mercury. Everything else about the host lives in
# configuration.nix / home.nix.
{ ... }:
{
  # The router's DNS keeps every old DHCP lease for "mercury" and hands them
  # out first, so the bare name times out on dead addresses. The tailnet name
  # always points at the live board.
  address = "mercury.ts.cramt.dk";
}

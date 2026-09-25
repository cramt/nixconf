{
  config,
  pkgs,
  ...
}: {
  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    hyprland.enable = false;
    niri.enable = true;
    bundles.general.enable = true;
    bundles.development.enable = true;
    btop.hardware-accel = "rocm";
    bundles.graphical.enable = true;
    bundles.gaming.enable = true;
    helium.enable = true;
    agentsview.enable = true;
    agentsview.service.enable = true;
    # Diagnostic for the intermittent WAN loss seen 2026-07-30 (affected multiple
    # devices, cleared on its own, every local component measured clean afterwards).
    # Turn off once the ISP-side cause is identified or ruled out.
    netwatch.enable = true;
    monitors = import ./monitors.nix;
    waybar.monitors = ["DP-2"];
  };

  home.packages = [
    (import ../../scripts/keep_awake.nix { inherit pkgs; })
    # Disabled: zed-delta is a requireFile package (invite-only download), so CI
    # can't produce it and the saturn build fails on it every run. Re-enable once
    # delta.dev serves the tarball without a session cookie and the package is
    # switched to fetchurl. Saturn only even then, not the graphical bundle.
    # pkgs.zed-delta
  ];

  home.stateVersion = "26.05";
}

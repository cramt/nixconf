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
    delta.enable = true;
    btop.hardware-accel = "rocm";
    bundles.graphical.enable = true;
    # The Philips 49M2C8900 is shared between mars and saturn.
    monitor-kvm.enable = true;
    bundles.gaming.enable = true;
    helium.enable = true;
    agentsview.enable = true;
    # Copied into saturn's Windows at each logon (windows.nix, wsl.linux.files).
    claude-code.windows.enable = true;
    # What to check on the next Windows boot; drop it once the report's in.
    claude-code.windows.testPlan = ./windows-tests.md;
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
    pkgs.vintagestoryPackages.latest
    pkgs.bs-sync
  ];

  home.stateVersion = "26.05";
}

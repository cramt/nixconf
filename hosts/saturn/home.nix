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

  # Felix as the client `nix`: the per-user profile precedes the system path,
  # so evaluation runs on Felix while root (sudo nixos-rebuild, which opens the
  # store directly) and the daemon stay on stock Lix. See packages/felix.
  home.packages = [
    (import ../../scripts/keep_awake.nix { inherit pkgs; })
    pkgs.felix
  ];

  home.stateVersion = "26.05";
}

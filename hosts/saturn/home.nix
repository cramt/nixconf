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
    paseo.enable = true;
    # Pools the Claude subscription accounts behind one local endpoint; the
    # `claude` wrapper in claude-code.nix picks this up automatically. Accounts
    # are added once each with `agent-accounts add` (interactive OAuth).
    cli-proxy-api.enable = true;
    agentsview.enable = true;
    agentsview.service.enable = true;
    # Diagnostic for the intermittent WAN loss seen 2026-07-30 (affected multiple
    # devices, cleared on its own, every local component measured clean afterwards).
    # Turn off once the ISP-side cause is identified or ruled out.
    netwatch.enable = true;
    obs.enable = true;
    jujutsu.enable = true;
    monitors = import ./monitors.nix;
    waybar.monitors = ["DP-2"];
  };

  home.packages = [
    (import ../../scripts/keep_awake.nix { inherit pkgs; })
  ];

  home.stateVersion = "26.05";
}

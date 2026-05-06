{
  config,
  pkgs,
  ...
}: {
  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    hyprland.enable = false;
    bundles.general.enable = true;
    bundles.development.enable = true;
    btop.hardware-accel = "rocm";
    bundles.graphical.enable = true;
    bundles.gaming.enable = true;
    helium.enable = true;
    obs.enable = true;
    jujutsu.enable = true;
    monitors = import ./monitors.nix;
    waybar.monitors = ["DP-2"];
  };

  home.packages = let
    open-openclaw = import ../../scripts/open_openclaw.nix { inherit pkgs; };
  in [
    open-openclaw
    (pkgs.makeDesktopItem {
      name = "openclaw";
      desktopName = "OpenClaw";
      comment = "Local LLM chat via OpenClaw gateway";
      exec = "${open-openclaw}/bin/open-openclaw";
      icon = "applications-science";
      categories = [ "Network" "Chat" ];
    })
    (import ../../scripts/keep_awake.nix { inherit pkgs; })
  ];

  home.stateVersion = "25.11";
}

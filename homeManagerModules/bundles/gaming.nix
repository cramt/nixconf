{
  pkgs,
  inputs,
  ...
}: {
  home.packages = with pkgs; [
    xorg.libxcb
    protonup-ng
    gamemode
    dxvk
    gamescope
    mangohud
    (wineWowPackages.full.override {
      wineRelease = "staging";
      mingwSupport = true;
    })
    winetricks
    inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.melonDS
    prismlauncher
    heroic
    bottles
  ];

  stylix.targets.steam = {
    enable = true;
    adwaitaForSteam.enable = true;
  };

  myHomeManager = {
    wowup.enable = true;
    cockatrice.enable = true;
  };

  # this is to make "wine system tray" not show up as a seperate stupid window
  # delete when can cause it pulls in a shitton of kde stuff
  services.xembed-sni-proxy.enable = true;
}

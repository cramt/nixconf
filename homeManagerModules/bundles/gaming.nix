{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.nix-flatpak.homeManagerModules.nix-flatpak
  ];
  home.packages = with pkgs; [
    xorg.libxcb
    gamemode
    dxvk
    gamescope
    mangohud
    (wineWowPackages.full.override {
      mingwSupport = true;
    })
    winetricks
    inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.melonDS
    prismlauncher
    lutris
    heroic
  ];

  services.flatpak = {
    enable = false;
    packages = [
    ];
  };

  myHomeManager = {
    wowup.enable = true;
    cockatrice.enable = true;
    nonsteamlauncher.enable = false;
  };

  # this is to make "wine system tray" not show up as a seperate stupid window
  # delete when can cause it pulls in a shitton of kde stuff
  services.xembed-sni-proxy.enable = true;
}

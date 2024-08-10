{ pkgs, inputs, ... }: {
  home.packages = with pkgs; [
    xorg.libxcb
    lutris
    protonup
    gamemode
    dxvk
    gamescope
    mangohud
    wineWowPackages.staging
    winetricks
    inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.melonDS
    prismlauncher
    heroic
  ];

  myHomeManager = {
    wowup.enable = true;
    cockatrice.enable = true;
    wfinfo.enable = true;
  };
}

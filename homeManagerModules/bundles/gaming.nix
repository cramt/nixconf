{ pkgs, inputs, ... }: {
  home.packages = with pkgs; [
    xorg.libxcb
    lutris
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
  ];

  myHomeManager = {
    wowup.enable = true;
  };
}

{ pkgs, ... }:

let
  src = pkgs.fetchzip {
    url = "https://github.com/WFCD/WFinfo/releases/download/v9.6.3/WFInfo.zip";
    hash = "sha256-IONElrZ0X91aglFeKbeUVrKqp7rcZ26/oONLRh9sbR8=";
  };

in
{

  home.packages = [
    (pkgs.writeScriptBin "WFInfo" ''
      WINEPREFIX=/home/cramt/.steam/steam/steamapps/compatdata/230410/pfx ${pkgs.wineWowPackages.staging}/bin/wine ${src}/WFInfo.exe
    '')
  ];
}

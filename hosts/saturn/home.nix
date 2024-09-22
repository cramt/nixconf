{ input, inputs, outputs, config, pkgs, lib, ... }:
{

  imports = [ outputs.homeManagerModules.default ];

  home.username = "cramt";
  home.homeDirectory = "/home/cramt";


  home.packages = [
    ((import ../../scripts/sway_gaming.nix) {
      inherit pkgs;
      direction = 10000;
      output = "DP-2";
    })
  ];


  myHomeManager = {
    bundles.general.enable = true;
    bundles.graphical.enable = true;
    bundles.gaming.enable = true;
    git.signingKey = "C2B9D34D979B6063";
    sway.monitors = lib.attrsets.mapAttrs
      (_: value: value.sway_conf // {
        res = value.res;
        mode = "${toString value.res.width}x${toString value.res.height}@${value.refresh_rate}Hz";
      })
      (import ./monitors.nix);
  };

  home.stateVersion = "24.05";
}

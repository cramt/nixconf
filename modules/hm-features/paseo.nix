{ inputs, ... }: {
  hmModules.features.paseo = { config, lib, pkgs, ... }:
  let
    cfg = config.myHomeManager.paseo;
    # Electron GUI client. Built with paseo's own nixpkgs (see flake.nix input
    # comment), so the npmDepsHash matches upstream's sidecar and it builds
    # without an override.
    paseoDesktop = inputs.paseo.packages.${pkgs.stdenv.hostPlatform.system}.desktop;
  in {
    options.myHomeManager.paseo.enable = lib.mkEnableOption "myHomeManager.paseo";
    config = lib.mkIf cfg.enable {
      home.packages = [ paseoDesktop ];
    };
  };
}

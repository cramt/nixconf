{ ... }: {
  hmModules.features.paseo = { config, lib, pkgs, ... }:
  let
    cfg = config.myHomeManager.paseo;
    # Electron GUI client from inputs.paseo, with the npm-deps hash corrected in
    # our overlay (upstream's `[skip ci]` sidecar hash mismatches paseo's pinned
    # nixpkgs — see overlays/default.nix).
    paseoDesktop = pkgs.paseo-desktop;
  in {
    options.myHomeManager.paseo.enable = lib.mkEnableOption "myHomeManager.paseo";
    config = lib.mkIf cfg.enable {
      home.packages = [ paseoDesktop ];
    };
  };
}

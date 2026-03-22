{ ... }: {
  hmModules.features.t3code = { config, lib, pkgs, ... }: {
    options.myHomeManager.t3code.enable = lib.mkEnableOption "myHomeManager.t3code";
    config = lib.mkIf config.myHomeManager.t3code.enable {
      home.packages = [
        (pkgs.callPackage ../../packages/t3code/default.nix {
          inherit (pkgs) npinsSources;
        })
      ];
    };
  };
}

{ ... }: {
  flake.nixosModules."services.sunshine" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.sunshine;
  in {
    options.myNixOS.services.sunshine = {
      enable = lib.mkEnableOption "myNixOS.services.sunshine";
    };
    config = lib.mkIf cfg.enable {
      services.sunshine = {
        enable = true;
        autoStart = true;
        capSysAdmin = true;
        openFirewall = true;
        package = pkgs.sunshine;
      };
    };
  };
}

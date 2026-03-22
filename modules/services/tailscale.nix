{ ... }: {
  flake.nixosModules."services.tailscale" = {
    config,
    lib,
    ...
  }: let
    cfg = config.myNixOS.services.tailscale;
    site = import ../../myLib/site.nix;
  in {
    options.myNixOS.services.tailscale = {
      enable = lib.mkEnableOption "myNixOS.services.tailscale";
    };
    config = lib.mkIf cfg.enable {
      services.tailscale = {
        enable = true;
        authKeyFile = config.services.onepassword-secrets.secretPaths.tailscalePreauthKey;
        authKeyParameters = {
          preauthorized = true;
          baseURL = site.tailscale_base_url;
        };
      };
    };
  };
}

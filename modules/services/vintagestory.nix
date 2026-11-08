{inputs, ...}: {
  flake.nixosModules."services.vintagestory" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.vintagestory;
  in {
    imports = [inputs.vintagestory-nix.nixosModules.default];

    options.myNixOS.services.vintagestory = {
      enable = lib.mkEnableOption "myNixOS.services.vintagestory";
      dataDir = lib.mkOption {
        type = lib.types.str;
        description = "where worlds, mods and serverconfig.json live";
      };
    };

    config = lib.mkIf cfg.enable {
      services.vintagestory = {
        enable = true;
        package = pkgs.vintagestoryPackages.latest;
        # The game's default port: clients type it, so port-selector can't pick it.
        port = 42420;
        openFirewall = true;
      };

      # Upstream hardcodes state under /var/lib; bind dataDir over it so worlds
      # land on a big disk. StateDirectory still gets created first, then this
      # is mounted on top inside the unit's namespace.
      systemd.tmpfiles.settings.vintagestory.${cfg.dataDir}.d = {
        user = "vintagestory";
        group = "vintagestory";
        mode = "0750";
      };
      systemd.services.vintagestory.serviceConfig.BindPaths = [
        "${cfg.dataDir}:/var/lib/${config.services.vintagestory.dataPath}"
      ];
    };
  };
}

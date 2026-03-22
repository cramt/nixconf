# Docker with gVisor runtime and auto-prune
{ ... }: {
  flake.nixosModules."features.docker" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.docker;
  in {
    options.myNixOS.docker = {
      enable = lib.mkEnableOption "myNixOS.docker";
      httpPort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = "port to open dockerd's http to";
      };
    };
    config = lib.mkIf cfg.enable {
      networking.firewall = {
        allowedTCPPorts = lib.optionals (cfg.httpPort != null) [cfg.httpPort];
      };
      virtualisation.docker = {
        enable = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
          flags = ["--all"];
        };
        daemon.settings = {
          runtimes = {
            runsc.path = "${pkgs.gvisor}/bin/runsc";
          };
          hosts =
            [
              "unix:///var/run/docker.sock"
            ]
            ++ (lib.optionals (cfg.httpPort != null) ["127.0.0.1:${builtins.toString cfg.httpPort}"]);
        };
      };
    };
  };
}

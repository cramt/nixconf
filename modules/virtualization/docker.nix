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
      # oci-containers defaults to podman. This used to be set by the
      # satisfactory module alone, so dropping satisfactory silently moved
      # every other container on luna to podman.
      virtualisation.oci-containers.backend = "docker";
      # Upstream leaves oci-containers units at TimeoutStartSec=0 so slow pulls
      # never time out. But a pre-start `docker load` that loses its containerd
      # lease hangs forever instead of failing, and at boot that holds
      # multi-user.target open: luna sat in "starting" for six days, and every
      # unit a later deploy added stayed dead because switch-to-configuration
      # only starts units whose target is active. A finite timeout turns the hang
      # into a failure that Restart=on-failure recovers from. Slowest healthy
      # start measured is ~3min (servatrice's image load), so 15min is headroom.
      systemd.services = lib.mapAttrs' (_: c:
        lib.nameValuePair c.serviceName {serviceConfig.TimeoutStartSec = lib.mkForce "15min";})
      config.virtualisation.oci-containers.containers;
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

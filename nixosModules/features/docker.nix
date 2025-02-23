{
  lib,
  config,
  ...
}: let
  cfg = config.myNixOS.docker;
in {
  options.myNixOS.docker = {
    httpPort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      description = ''
        port to open dockerd's http to
      '';
    };
  };
  config = {
    networking.firewall = {
      allowedTCPPorts = lib.optionals (cfg.httpPort != null) [cfg.httpPort];
    };
    virtualisation.docker = {
      enable = true;
      daemon.settings = {
        hosts =
          [
            "unix:///var/run/docker.sock"
          ]
          ++ (lib.optionals (cfg.httpPort != null) ["127.0.0.1:${builtins.toString cfg.httpPort}"]);
      };
    };
  };
}

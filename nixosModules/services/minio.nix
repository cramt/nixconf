{
  config,
  lib,
  pkgs,
  ...
}: let
  secrets = (import ../../secrets.nix).minio;

  ui_port = config.port-selector.ports.minio_ui;
  api_port = config.port-selector.ports.minio_api;
in {
  config = {
    myNixOS.services.caddy.serviceMap = {
      bucketapi = {
        port = api_port;
      };
      bucket = {
        port = ui_port;
      };
    };
    port-selector.auto-assign = ["minio_ui" "minio_api"];
    services.minio = {
      secretKey = secrets.secret_key;
      accessKey = secrets.access_key;
      listenAddress = ":${builtins.toString api_port}";
      consoleAddress = ":${builtins.toString ui_port}";
      dataDir = ["/storage/minio"];
      enable = true;
    };
  };
}

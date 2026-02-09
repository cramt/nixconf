{
  config,
  lib,
  pkgs,
  ...
}: let
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
      rootCredentialsFile = config.services.onepassword-secrets.secretPaths.minioCredsEnv;
      listenAddress = ":${builtins.toString api_port}";
      consoleAddress = ":${builtins.toString ui_port}";
      dataDir = ["/storage/minio"];
      enable = true;
    };
  };
}

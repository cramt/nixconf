{ ... }: {
  flake.nixosModules."services.minio" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.minio;
    ui_port = config.port-selector.ports.minio_ui;
    api_port = config.port-selector.ports.minio_api;
  in {
    options.myNixOS.services.minio = {
      enable = lib.mkEnableOption "myNixOS.services.minio";
    };
    config = lib.mkIf cfg.enable {
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
  };
}

{
  config,
  lib,
  pkgs,
  ...
}: let
  secrets = (import ../../secrets.nix).minio;
in {
  config = {
    myNixOS.services.caddy.serviceMap = {
      bucketapi = {
        port = 9000;
      };
      bucket = {
        port = 9001;
      };
    };
    services.minio = {
      secretKey = secrets.secret_key;
      accessKey = secrets.access_key;
      dataDir = ["/storage/minio"];
      enable = true;
    };
  };
}

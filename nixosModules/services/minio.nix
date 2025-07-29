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
      bucketapi = 9000;
      bucket = 9001;
    };
    services.minio = {
      secretKey = secrets.secret_key;
      accessKey = secrets.access_key;
      dataDir = ["/storage/minio"];
      enable = true;
    };
  };
}

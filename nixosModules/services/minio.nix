{
  config,
  lib,
  pkgs,
  ...
}: let
  secrets = (import ../../secrets.nix).minio;
in {
  config = {
    services.minio = {
      secretKey = secrets.secret_key;
      accessKey = secrets.access_key;
      dataDir = ["/storage/minio"];
      enable = true;
    };
  };
}

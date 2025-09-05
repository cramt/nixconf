{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.myNixOS.services.gtnh;
  gtnh_static_raw = pkgs.stdenv.mkDerivation {
    name = "gtnh-static-raw";
    src = pkgs.fetchurl {
      url = "https://downloads.gtnewhorizons.com/ServerPacks/GT_New_Horizons_2.7.4_Server_Java_17-21.zip";
      sha256 = "sha256-cPDC7AJTudRFF/vlp9THqmMep3AAe4zqKJUf74Ppizg=";
    };
    phases = ["installPhase"];
    nativeBuildInputs = [pkgs.unzip];
    installPhase = ''
      mkdir -p $out/bin
      unzip $src
      rm -rf *.sh
      rm -rf *.bat
      rm -rf *.md
      echo "eula=true" > eula.txt
      cp -r ./* $out/bin
    '';
  };
  gtnh = pkgs.writeShellApplication {
    name = "gtnh";
    runtimeInputs = [pkgs.temurin-jre-bin gtnh_static_raw];
    text = ''
      if [ -z "$( ls -A "$GTNH_FOLDER" )" ]; then
        mkdir -p "$GTNH_FOLDER"
        cp -r ${gtnh_static_raw}/bin/* "$GTNH_FOLDER"
        chmod 777 "$GTNH_FOLDER"
      fi
      cd "$GTNH_FOLDER"
      java -Xms12G -Xmx12G -Dfml.readTimeout=180 @java9args.txt -jar lwjgl3ify-forgePatches.jar nogui
    '';
  };
  dockerImage = pkgs.dockerTools.streamLayeredImage {
    name = "gtnh";
    tag = "1";
    contents = with pkgs; [
      coreutils
      cacert
      temurin-jre-bin
      gtnh
      gtnh_static_raw
    ];
    config = {
      Cmd = [
        "${gtnh}/bin/gtnh"
      ];
      Env = ["SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"];
    };
  };
  port = config.port-selector.ports.gtnh;
in {
  options.myNixOS.services.gtnh = {
    dataVolume = lib.mkOption {
      type = lib.types.str;
      description = ''
        destination for the data
      '';
    };
  };

  config = {
    port-selector.set-ports."25565" = "gtnh";
    virtualisation.oci-containers.containers.gtnh = {
      hostname = "gtnh";
      imageStream = dockerImage;
      image = "gtnh:1";
      volumes = [
        "${cfg.dataVolume}:/data"
      ];
      ports = [
        "${builtins.toString port}:25565"
      ];
      environment = {
        GTNH_FOLDER = "/data";
      };
      autoStart = false;
    };
  };
}

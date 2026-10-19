# Declarative wifi (wpa_supplicant) with PSKs from opnix (1Password).
#
# wpa_supplicant's `ext:` passwords read `name=value` lines from secretsFile,
# while opnix renders a field's bare value, so a oneshot composes the one from
# the others once opnix has run. opnix fetches over the network, so on a fresh
# flash the first fetch has to come over ethernet (or anything not this wifi);
# after that the rendered secrets survive reboots.
{ ... }: {
  flake.nixosModules."networking.wifi" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.wifi;
    ucfirst = s: (lib.toUpper (builtins.substring 0 1 s)) + (builtins.substring 1 (-1) s);
    # opnix requires camelCase secret keys.
    secretName = name: "wifiPsk${ucfirst name}";
    secretsFile = "/run/wpa_supplicant-secrets/psks";
    supplicantUnits =
      if config.networking.wireless.interfaces == [ ]
      then [ "wpa_supplicant.service" ]
      else map (i: "wpa_supplicant-${i}.service") config.networking.wireless.interfaces;
  in {
    options.myNixOS.wifi = {
      enable = lib.mkEnableOption "declarative wifi with PSKs from opnix";

      networks = lib.mkOption {
        default = { };
        description = "Networks to join. The attribute name is a short camelCase id (e.g. `home`).";
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            ssid = lib.mkOption {
              type = lib.types.str;
              example = "The Gayze";
            };
            pskRef = lib.mkOption {
              type = lib.types.str;
              example = "op://Homelab/li32dfrut7k2gsqwvp4srqitc4/wireless_password";
              description = "opnix reference to the WPA passphrase.";
            };
          };
        });
      };
    };

    config = lib.mkIf (cfg.enable && cfg.networks != { }) {
      services.onepassword-secrets = {
        enable = true;
        tokenFile = lib.mkDefault "/etc/opnix-token";
        secrets = lib.mapAttrs' (name: net:
          lib.nameValuePair (secretName name) {
            reference = net.pskRef;
            mode = "0600";
          })
          cfg.networks;
      };

      networking.wireless = {
        enable = true;
        inherit secretsFile;
        networks = lib.mapAttrs' (name: net:
          lib.nameValuePair net.ssid { pskRaw = "ext:psk_${name}"; })
          cfg.networks;
      };

      systemd.services.wifi-psks = {
        description = "Compose wpa_supplicant's secretsFile from opnix";
        after = [ "opnix-secrets.service" ];
        wants = [ "opnix-secrets.service" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          set -eu
          install -d -m700 -o wpa_supplicant -g wpa_supplicant ${dirOf secretsFile}
          tmp=$(mktemp ${dirOf secretsFile}/.psks.XXXXXX)
          ${lib.concatStrings (lib.mapAttrsToList (name: _: ''
            printf 'psk_${name}=%s\n' "$(tr -d '\n' < ${config.services.onepassword-secrets.secretPaths.${secretName name}})" >> "$tmp"
          '') cfg.networks)}
          chown wpa_supplicant:wpa_supplicant "$tmp"
          chmod 400 "$tmp"
          mv "$tmp" ${secretsFile}
          # Don't make wpa_supplicant wait on opnix (which waits on the network);
          # bounce it once the PSKs exist instead.
          ${pkgs.systemd}/bin/systemctl try-restart ${lib.concatStringsSep " " supplicantUnits} || true
        '';
      };

      # BindReadOnlyPaths in the supplicant unit fails if the file is missing.
      systemd.tmpfiles.rules = [
        "d ${dirOf secretsFile} 0700 wpa_supplicant wpa_supplicant -"
        "f ${secretsFile} 0400 wpa_supplicant wpa_supplicant -"
      ];
    };
  };
}

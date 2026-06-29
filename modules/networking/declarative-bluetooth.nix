# Declarative BlueZ bonds, re-seeded from opnix (1Password).
#
# A Bluetooth pairing lives on the host at /var/lib/bluetooth/<adapter>/<device>/
# (the `info` file holds the long-term keys), so a full disk/SD reflash wipes it
# and you'd have to re-pair. This module stores each device's `info` file as a
# 1Password secret and, on every boot, fetches it via opnix and installs it back
# into place, then nudges bluetooth to load it — so bonds survive reflashes.
#
# It is deliberately self-contained: enabling it pulls in ONLY the bond secrets
# (not any other host's opnix secret bundle), so it's reusable on any host for
# any already-bonded device. Pair the device once by hand, stash its `info` file
# in 1Password, then declare it here.
{ ... }: {
  flake.nixosModules."networking.declarative-bluetooth" = { config, lib, pkgs, ... }:
  let
    cfg = config.myNixOS.declarativeBluetooth;
    ucfirst = s: (lib.toUpper (builtins.substring 0 1 s)) + (builtins.substring 1 (-1) s);
    # opnix requires camelCase secret keys, so derive one per device id.
    secretName = name: "bluetoothBond${ucfirst name}";
  in {
    options.myNixOS.declarativeBluetooth = {
      enable = lib.mkEnableOption "declarative BlueZ bonds re-seeded from opnix";

      tokenFile = lib.mkOption {
        type = lib.types.path;
        default = "/etc/opnix-token";
        description = "1Password service-account token file used by opnix.";
      };

      devices = lib.mkOption {
        default = {};
        description = ''
          Bonded Bluetooth devices to re-seed declaratively. The attribute name
          is a short camelCase id (e.g. `steamController`).

          To onboard a device: pair it once normally, then copy
          /var/lib/bluetooth/<adapter>/<address>/info into a 1Password field and
          point `secretRef` at it.
        '';
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            adapter = lib.mkOption {
              type = lib.types.str;
              example = "DC:A6:32:0B:27:48";
              description = "MAC of this host's Bluetooth adapter. Stable across reflashes (it's in the radio).";
            };
            address = lib.mkOption {
              type = lib.types.str;
              example = "F8:FC:54:D5:6A:06";
              description = "MAC the device is bonded under (its identity/static address).";
            };
            secretRef = lib.mkOption {
              type = lib.types.str;
              example = "op://Homelab/SteamControllerBond/info";
              description = "opnix reference to the BlueZ `info` bond-file contents.";
            };
          };
        });
      };
    };

    config = lib.mkIf (cfg.enable && cfg.devices != {}) {
      assertions = [{
        assertion = config.hardware.bluetooth.enable;
        message = "myNixOS.declarativeBluetooth requires hardware.bluetooth.enable = true.";
      }];

      # Pull ONLY the bond secrets, so enabling this doesn't drag in the rest of
      # a host's opnix configuration. tokenFile is mkDefault so a host that also
      # uses myNixOS.opnix-secrets keeps a single shared token definition.
      services.onepassword-secrets = {
        enable = true;
        tokenFile = lib.mkDefault cfg.tokenFile;
        secrets = lib.mapAttrs' (name: dev:
          lib.nameValuePair (secretName name) {
            reference = dev.secretRef;
            mode = "0600";
          })
          cfg.devices;
      };

      # opnix fetches secrets after the network is up (so well after bluetooth
      # has already started); rather than block bluetooth on the network, seed
      # the bond once the secret lands and then restart bluetooth to load it.
      systemd.services = lib.mapAttrs' (name: dev:
        lib.nameValuePair "bluetooth-bond-${name}" {
          description = "Seed BlueZ bond for ${name} from its opnix secret";
          after = [ "opnix-secrets.service" ];
          wants = [ "opnix-secrets.service" ];
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ''
            set -eu
            src=${config.services.onepassword-secrets.secretPaths.${secretName name}}
            dir=/var/lib/bluetooth/${dev.adapter}/${dev.address}
            install -d -m700 -o root -g root "$dir"
            install -m600 -o root -g root "$src" "$dir/info"
            # BlueZ only reads bonds at startup; reload it now that the bond exists.
            ${pkgs.systemd}/bin/systemctl try-restart bluetooth.service || true
          '';
        })
        cfg.devices;
    };
  };
}

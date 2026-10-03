# Moonlight: this host streams from the gaming desktop's Sunshine
# (modules/gaming/sunshine.nix), already paired. The pairing is generated
# ahead of time (moonlight-pairing.json plus this client's key in 1Password,
# docs/moonlight-pairing.md), and seeded into Moonlight.conf at every
# graphical session start.
{...}: {
  flake.nixosModules."features.moonlight" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.moonlight;
    pairing = lib.importJSON ./moonlight-pairing.json;
    hostName = config.networking.hostName;
    client = pairing.clients.${hostName};
    keyPath = config.services.onepassword-secrets.secretPaths.moonlightClientKey;

    seed = pkgs.writeShellApplication {
      name = "moonlight-pairing-seed";
      text = ''
        exec ${lib.getExe pkgs.moonlight-seed} \
          --cert ${pkgs.writeText "moonlight-${hostName}-cert.pem" client.cert} \
          --key ${keyPath} \
          --uniqueid ${client.uniqueid} \
          --host-uuid ${pairing.server.uniqueid} \
          --host-name ${cfg.host.name} \
          --host-address ${cfg.host.address} \
          --host-mac ${cfg.host.macAddress} \
          --host-cert ${pkgs.writeText "sunshine-cert.pem" pairing.server.cert}
      '';
    };
  in {
    options.myNixOS.moonlight = {
      enable = lib.mkEnableOption "myNixOS.moonlight";

      user = lib.mkOption {
        type = lib.types.str;
        description = "The user whose Moonlight gets the pairing.";
      };

      host = {
        name = lib.mkOption {
          type = lib.types.str;
          description = "The gaming desktop's name, as its Sunshine reports it (sunshine_name).";
        };
        address = lib.mkOption {
          type = lib.types.str;
          description = "Where to reach it. Moonlight updates this itself once it has connected.";
        };
        macAddress = lib.mkOption {
          type = lib.types.str;
          description = ''
            Its wired MAC. Moonlight only learns it from a connection, so it
            couldn't wake the host for its first one without this.
          '';
        };
      };

      clientKey = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "op://Homelab/Moonlight-ganymede/moonlight-ganymede.pem";
        description = ''
          1Password file reference to this client's private key. Null leaves
          Moonlight unpaired: opnix renders every secret or none, so a
          reference to an item that doesn't exist yet would take the host's
          other secrets down with it.
        '';
      };
    };

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
        assertions = [
          {
            assertion = pairing.clients ? ${hostName};
            message = "moonlight-pairing.json has no client named ${hostName}; re-run `nix run .#moonlight-pairing` with it";
          }
        ];
        environment.systemPackages = [pkgs.moonlight-qt];
      }

      (lib.mkIf (cfg.clientKey != null) {
        services.onepassword-secrets.secrets.moonlightClientKey = {
          reference = cfg.clientKey;
          kind = "file";
          owner = cfg.user;
          mode = "0400";
        };

        # Moonlight rewrites Moonlight.conf as it runs (host addresses, app
        # lists, its preferences), so the pairing is put back into it rather
        # than the file being owned: moonlight-seed sets only the client
        # identity and this host's entry, every session start. A rotated
        # pairing lands with the next session, and nothing done in
        # Moonlight's UI (unpairing, a PIN pairing) outlives one.
        systemd.user.services.moonlight-pairing = {
          description = "Seed Moonlight with its pre-generated pairing";
          wantedBy = ["graphical-session.target"];
          before = ["graphical-session.target"];
          unitConfig.ConditionUser = cfg.user;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = lib.getExe seed;
          };
        };
      })
    ]);
  };
}

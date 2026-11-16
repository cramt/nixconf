# 1Password secrets on a phone, the same way as on hosts (modules/security/
# secrets.nix): myNixup.secrets.<name> declares one, and an op-secrets unit,
# run by Nixup's engine, renders it with op-secrets.sh to
# myNixup.secrets.<name>.path. Consumers take that path as a string, which
# Nixup reads as "a file already on the phone".
#
# The one thing it can't fetch itself is the service-account token. nixup-rebuild
# ships it from the machine doing the rebuild, the way `just install` carries it
# onto a wiped host: an android.secrets file is read where it is and sent to
# /data/adb/nixup/secrets, never copied into the store.
#
# Unlike hosts, a changed value doesn't restart the consumers: the phone has no
# systemctl. `services` only orders them after the render.
{ ... }:
let
  consts = import ../../myLib/secrets.nix;
in
{
  nixupModules.secrets = { config, lib, pkgs, ... }:
    let
      secrets = config.myNixup.secrets;

      manifest = pkgs.writeText "op-secrets.jsonl" (lib.concatMapStrings (s:
        builtins.toJSON {
          inherit (s) name reference path mode;
          owner = "root";
          group = "root";
          # Empty, so op-secrets.sh never reaches for systemctl.
          services = [ ];
        } + "\n") (lib.attrValues secrets));

      render = pkgs.writeShellApplication {
        name = "op-secrets";
        runtimeInputs = with pkgs; [ _1password-cli coreutils diffutils jq ];
        text = builtins.readFile ../security/op-secrets.sh;
      };

      consumers = lib.unique (lib.concatMap (s: s.services) (lib.attrValues secrets));
    in
    {
      options.myNixup.secrets = lib.mkOption {
        default = { };
        description = "1Password secrets rendered on the phone by its op-secrets unit.";
        type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
          options = {
            name = lib.mkOption {
              type = lib.types.strMatching "[A-Za-z0-9_-]+";
              default = name;
              readOnly = true;
              internal = true;
            };
            reference = lib.mkOption {
              type = lib.types.strMatching "op://.+";
              description = "Secret reference to a field or a file attachment.";
            };
            path = lib.mkOption {
              type = lib.types.str;
              default = "${consts.dir}/${name}";
              readOnly = true;
            };
            mode = lib.mkOption {
              type = lib.types.strMatching "0?[0-7]{3}";
              default = "0600";
            };
            services = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Units (without `.service`) that read it: they start after op-secrets.";
            };
          };
        }));
      };

      config = lib.mkIf (secrets != { }) {
        android.secrets.op-token.file = /. + consts.tokenFile;

        # Unfree, so Hydra doesn't build it; the phone unpacks the binary itself.
        nixpkgs.config.allowUnfreePredicate = pkg: lib.getName pkg == "1password-cli";

        systemd.services = {
          op-secrets = {
            description = "Render 1Password secrets";
            wantedBy = [ "multi-user.target" ];
            # Phones come and go off the network: keep retrying, like hosts do.
            unitConfig.StartLimitIntervalSec = 0;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart = "${lib.getExe render} ${manifest} ${config.android.secrets.op-token.path} ${consts.dir}";
              Restart = "on-failure";
              RestartSec = "30s";
              TimeoutStartSec = "5min";
              # op keeps its config dir under $HOME.
              RuntimeDirectory = "op-secrets";
              Environment = "HOME=%t/op-secrets";
            };
          };
        } // lib.genAttrs consumers (_: {
          after = [ "op-secrets.service" ];
          wants = [ "op-secrets.service" ];
        });
      };
    };
}

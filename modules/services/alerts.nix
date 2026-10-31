# Not-really-on-call: prometheus evaluates alert rules, alertmanager groups and
# dedupes them, and alert-dm turns each one into a Discord DM from the yelliv
# bot (the same one the dm-me skill uses). Rules come from whichever module
# owns the thing being watched, via `alertRules`, so a disabled service never
# leaves a dangling alert behind.
{...}: {
  flake.nixosModules."services.alerts" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.alerts;
    ports = config.port-selector.ports;
  in {
    options.myNixOS.services.alerts = {
      enable = lib.mkEnableOption "myNixOS.services.alerts";
      recipient = lib.mkOption {
        type = lib.types.str;
        default = "149996010314137600";
        description = "Discord user ID the DMs go to (Alex).";
      };
      alertRules = lib.mkOption {
        type = lib.types.attrsOf (lib.types.listOf lib.types.attrs);
        default = {};
        example = {
          disks = [
            {
              alert = "DiskFull";
              expr = ''node_filesystem_avail_bytes / node_filesystem_size_bytes < 0.05'';
              "for" = "15m";
              annotations.summary = "{{ $labels.mountpoint }} is nearly full";
            }
          ];
        };
        description = ''
          Prometheus alerting rules, keyed by rule group. `annotations.summary`
          is the DM's first line, `annotations.description` the rest.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.myNixOS.services.metrics.server.enable;
          message = "myNixOS.services.alerts evaluates rules on the fleet prometheus, so it needs myNixOS.services.metrics.server.";
        }
      ];

      port-selector.auto-assign = ["alertmanager" "alert_dm"];

      services.prometheus = {
        rules = [
          (builtins.toJSON {
            groups = lib.mapAttrsToList (name: rules: {inherit name rules;}) cfg.alertRules;
          })
        ];
        alertmanagers = [
          {static_configs = [{targets = ["127.0.0.1:${toString ports.alertmanager}"];}];}
        ];
        alertmanager = {
          enable = true;
          port = ports.alertmanager;
          listenAddress = "127.0.0.1";
          configuration = {
            route = {
              receiver = "discord-dm";
              group_by = ["..."];
              group_wait = "30s";
              group_interval = "5m";
              # A still-broken thing nags twice a day, not every few minutes.
              repeat_interval = "12h";
            };
            receivers = [
              {
                name = "discord-dm";
                webhook_configs = [
                  {
                    url = "http://127.0.0.1:${toString ports.alert_dm}/";
                    send_resolved = true;
                  }
                ];
              }
            ];
          };
        };
      };

      services.onepassword-secrets.secrets.yellivBotToken = {
        reference = "op://Homelab/OpenClaw-Discord/botToken";
        services = ["alert-dm"];
      };

      systemd.services.alert-dm = {
        description = "Alertmanager webhook -> Discord DM";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = ["network-online.target"];
        environment = {
          ALERT_DM_LISTEN = "http://127.0.0.1:${toString ports.alert_dm}";
          ALERT_DM_RECIPIENT = cfg.recipient;
        };
        serviceConfig = {
          ExecStart = lib.getExe pkgs.alert-dm;
          DynamicUser = true;
          LoadCredential = ["bot-token:${config.services.onepassword-secrets.secretPaths.yellivBotToken}"];
          Restart = "on-failure";
        };
      };
    };
  };
}

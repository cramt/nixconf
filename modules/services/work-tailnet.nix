# A second tailnet next to the fleet one (myNixOS.services.tailscale), for a
# host that also has to reach someone else's (work's) machines.
#
# The fleet tailscaled owns tailscale0, the 100.64.0.0/10 route, routing table
# 52 and the system DNS. A second kernel-mode daemon would fight it for all of
# that, so this one runs in userspace: no interface, no routes, no DNS. Traffic
# goes out through its proxies instead, which also resolve that tailnet's
# MagicDNS names:
#   ssh:     ProxyCommand tailscale-work nc %h %p
#   other:   SOCKS5 on localhost:<socksPort>, HTTP proxy on localhost:<httpProxyPort>
#
# Shields up by default: a userspace node hands incoming connections to
# localhost, which would put everything bound there in reach of a tailnet
# whose ACLs we don't control.
{ ... }: {
  flake.nixosModules."services.work-tailnet" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.work-tailnet;
    tailscale = config.services.tailscale.package;
    socket = "/run/tailscale-work/tailscaled.sock";
    cli = pkgs.writeShellScriptBin "tailscale-work" ''
      exec ${lib.getExe tailscale} --socket=${socket} "$@"
    '';
  in {
    options.myNixOS.services.work-tailnet = {
      enable = lib.mkEnableOption "a second, userspace tailscaled for the work tailnet";
      authKeyReference = lib.mkOption {
        type = lib.types.strMatching "op://.+";
        description = "1Password reference to the auth key work hands out (an auth key or an OAuth client secret).";
      };
      loginServer = lib.mkOption {
        type = lib.types.str;
        default = "https://controlplane.tailscale.com";
        description = "Work's control server; set it if they run headscale.";
      };
      extraUpFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [];
        example = ["--advertise-tags=tag:alex"];
        description = "Extra `tailscale up` flags, e.g. the tags an OAuth client secret requires.";
      };
      acceptIncoming = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Drop shields-up. Anything listening on localhost becomes reachable from the work tailnet.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 41642;
        description = "WireGuard UDP port; the fleet tailscaled has 41641.";
      };
      socksPort = lib.mkOption {
        type = lib.types.port;
        default = 1055;
      };
      httpProxyPort = lib.mkOption {
        type = lib.types.port;
        default = 1056;
      };
    };

    config = lib.mkIf cfg.enable {
      myNixOS.secrets.workTailnetAuthKey = {
        reference = cfg.authKeyReference;
        services = ["tailscaled-work-up"];
      };

      environment.systemPackages = [cli];
      # Direct connections instead of DERP relays; nothing else listens here.
      networking.firewall.allowedUDPPorts = [cfg.port];

      systemd.services.tailscaled-work = {
        description = "Tailscale node agent for the work tailnet (userspace)";
        wantedBy = ["multi-user.target"];
        after = ["network-online.target"];
        wants = ["network-online.target"];
        serviceConfig = {
          ExecStart = lib.escapeShellArgs [
            "${tailscale}/bin/tailscaled"
            "--tun=userspace-networking"
            "--statedir=/var/lib/tailscale-work"
            "--socket=${socket}"
            "--port=${toString cfg.port}"
            "--socks5-server=localhost:${toString cfg.socksPort}"
            "--outbound-http-proxy-listen=localhost:${toString cfg.httpProxyPort}"
          ];
          StateDirectory = "tailscale-work";
          StateDirectoryMode = "0700";
          RuntimeDirectory = "tailscale-work";
          Restart = "on-failure";
        };
      };

      # Like the fleet's tailscaled-autoconnect, but a node that's already in
      # gets `set` on every start, so a changed flag lands on the next switch
      # without a re-login.
      systemd.services.tailscaled-work-up = {
        description = "Join the work tailnet";
        after = ["tailscaled-work.service"];
        requires = ["tailscaled-work.service"];
        wantedBy = ["multi-user.target"];
        path = [cli pkgs.jq];
        serviceConfig = {
          Type = "oneshot";
          # Active after it exits, so switch-to-configuration restarts it
          # when its flags change.
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = 30;
        };
        unitConfig.StartLimitIntervalSec = 0;
        script = let
          # What `set` also takes; login server and tags only change on a
          # fresh `up`.
          setFlags = [
            "--hostname=${config.networking.hostName}"
            "--shields-up=${lib.boolToString (!cfg.acceptIncoming)}"
            # So `tailscale-work nc` works as cramt, for ssh's ProxyCommand.
            "--operator=cramt"
          ];
          upFlags = ["--login-server=${cfg.loginServer}"] ++ setFlags ++ cfg.extraUpFlags;
        in ''
          for _ in $(seq 30); do
            tailscale-work status --json >/dev/null 2>&1 && break
            sleep 1
          done
          key="$(cat ${config.myNixOS.secrets.workTailnetAuthKey.path})"
          # An OAuth client secret only mints a key with these appended.
          case $key in tskey-client-*) key="$key?ephemeral=false&preauthorized=true" ;; esac
          if [ "$(tailscale-work status --json | jq -r .BackendState)" = Running ]; then
            tailscale-work set ${lib.escapeShellArgs setFlags}
          else
            tailscale-work up --reset --auth-key "$key" ${lib.escapeShellArgs upFlags}
          fi
        '';
      };
    };
  };
}

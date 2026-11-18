# The work tailnet as a second profile of the fleet tailscaled (Tailscale's
# fast user switching): one tailnet at a time, `tailscale switch work` /
# `tailscale switch personal`, no sudo. Boot always comes up on personal.
#
# Two at once would mean a second daemon, and two kernel-mode ones collide
# (both own routing table 52, the 100.64.0.0/10 DROP in ts-input, and
# 100.100.100.100); the ways around that (userspace + SOCKS, a netns per
# tailnet) cost a proxy or a wrapper on every tool. Upstream tracks real
# multi-tailnet support in tailscale/tailscale#183.
#
# While work is active this host is off the fleet tailnet: no T3 Code links,
# no build pool, no deploys over the tailnet.
{ ... }: {
  flake.nixosModules."services.work-tailnet" = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myNixOS.services.work-tailnet;
    site = import ../../myLib/site.nix;
    waitForDaemon = ''
      for _ in $(seq 30); do
        tailscale status --json >/dev/null 2>&1 && break
        sleep 1
      done
    '';
    hasProfile = ''has() { tailscale switch --list --json | jq -e --arg n "$1" 'any(.[]; .nickname == $n)' >/dev/null; }'';
  in {
    options.myNixOS.services.work-tailnet = {
      enable = lib.mkEnableOption "the work tailnet as a switchable profile of the fleet tailscaled";
      authKeyReference = lib.mkOption {
        type = lib.types.strMatching "op://.+";
        description = "1Password reference to work's auth key (reusable, or the profile can't be recreated).";
      };
      loginServer = lib.mkOption {
        type = lib.types.str;
        default = "https://controlplane.tailscale.com";
        description = "Work's control server; set it if they run headscale.";
      };
    };

    config = lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.myNixOS.services.tailscale.enable;
          message = "myNixOS.services.work-tailnet is a profile of the fleet tailscaled; enable myNixOS.services.tailscale.";
        }
      ];

      myNixOS.secrets.workTailnetAuthKey = {
        reference = cfg.authKeyReference;
        services = ["tailscale-work-profile"];
      };

      # Makes sure both profiles exist and carry their names, then leaves
      # whichever one was active alone, so a deploy never kicks you off work.
      systemd.services.tailscale-work-profile = {
        description = "Add the work tailnet as a tailscale profile";
        after = ["tailscaled-autoconnect.service"];
        wants = ["tailscaled-autoconnect.service"];
        wantedBy = ["multi-user.target"];
        path = [config.services.tailscale.package pkgs.jq];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          Restart = "on-failure";
          RestartSec = 30;
        };
        unitConfig.StartLimitIntervalSec = 0;
        script = ''
          ${waitForDaemon}
          ${hasProfile}
          if ! has personal; then
            # Only the fleet profile may be named personal; on a fresh host
            # autoconnect has just logged it in, so it's the active one.
            suffix=$(tailscale status --json | jq -r .MagicDNSSuffix)
            if [ "$suffix" != "${site.tailnet_domain}" ]; then
              echo "active profile is on $suffix, not the fleet tailnet; not naming it personal" >&2
              exit 1
            fi
            tailscale set --nickname=personal --operator=cramt
          fi
          if ! has work; then
            # login adds a profile and switches to it; back to personal after.
            # Shields up: tailscale0 is a trusted interface here, which is
            # only safe on the fleet tailnet.
            tailscale login --auth-key "$(cat ${config.myNixOS.secrets.workTailnetAuthKey.path})" \
              --login-server=${cfg.loginServer} --nickname=work --operator=cramt \
              --shields-up --hostname=${config.networking.hostName}
            tailscale switch personal
          fi
        '';
      };

      # tailscaled resumes whichever profile was last active; boot always
      # starts on the fleet one. Before autoconnect, so a profile needing
      # login is never fed the fleet key while work is selected.
      systemd.services.tailscale-boot-personal = {
        description = "Start on the personal tailscale profile";
        after = ["tailscaled.service"];
        requires = ["tailscaled.service"];
        before = ["tailscaled-autoconnect.service"];
        wantedBy = ["multi-user.target"];
        # Boot only: a deploy restarting this would switch away from work.
        restartIfChanged = false;
        path = [config.services.tailscale.package pkgs.jq];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${waitForDaemon}
          ${hasProfile}
          if has personal; then tailscale switch personal; fi
        '';
      };
    };
  };
}

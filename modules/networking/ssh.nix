# SSH — NixOS agent config + HM client with 1Password
{ ... }:
let
  site = import ../../myLib/site.nix;
in {
  flake.nixosModules."features.ssh" = { config, lib, ... }: {
    options.myNixOS.ssh.enable = lib.mkEnableOption "myNixOS.ssh";
    config = lib.mkIf config.myNixOS.ssh.enable {
      programs.ssh.startAgent = false;
    };
  };

  hmModules.features.ssh = { config, lib, pkgs, ... }:
  let
    sshTargets = {
      luna = "-t cramt@${site.luna_internal_address} -A";
      remote_luna = "-t cramt@${site.ip} -p 2269 -A";
      jump = "ao@161.35.219.109 -A";
    };
    sshTargetPackages = builtins.mapAttrs (name: value: pkgs.writeScriptBin "ssh_${name}" "ssh ${value}") sshTargets;
    sshTargetDesktops =
      builtins.mapAttrs
      (name: value:
        pkgs.makeDesktopItem {
          name = "ssh-${name}";
          desktopName = "ssh ${name}";
          exec = "${pkgs.ghostty}/bin/ghostty -e ${pkgs.zsh}/bin/zsh -c ${value}/bin/ssh_${name}";
        })
      sshTargetPackages;
  in {
    options.myHomeManager.ssh = {
      enable = lib.mkEnableOption "myHomeManager.ssh";
      desktopEntries = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install a launcher per ssh target that opens it in ghostty. Pointless
          on a headless host, and it makes ghostty part of the closure.
        '';
      };
      use1Password = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to route ssh client auth through the 1Password agent
          (sets IdentityAgent for Host *, writes the 1Password agent.toml,
          and autostarts the 1Password desktop app). Disable on headless
          hosts where 1Password is not installed.
        '';
      };
    };
    config = lib.mkIf config.myHomeManager.ssh.enable (lib.mkMerge [
      {
        programs.ssh = {
          enable = true;
          enableDefaultConfig = false;
          settings = {
            "*" = {
              ControlPath = "~/.ssh/control-%C";
            };
            # Named Host aliases so plain `ssh luna` etc. resolve.
            "luna" = {
              HostName = site.luna_internal_address;
              User = "cramt";
              ForwardAgent = true;
            };
            # Same box over WAN (matches the remote_luna helper: public IP, port 2269).
            "luna-remote" = {
              HostName = site.ip;
              Port = 2269;
              User = "cramt";
              ForwardAgent = true;
            };
          };
        };
        home.packages =
          builtins.attrValues sshTargetPackages
          ++ lib.optionals config.myHomeManager.ssh.desktopEntries (builtins.attrValues sshTargetDesktops);
      }
      (lib.mkIf config.myHomeManager.ssh.use1Password {
        programs.ssh.settings."*".IdentityAgent = "~/.1password/agent.sock";

        xdg.configFile."1Password/ssh/agent.toml" = {
          text = ''
            [[ssh-keys]]
            item = "SSH Key - Personal"
          '';
        };

        # A unit, not an XDG autostart entry: 1Password exits on its own when
        # inotify sees its store dir change, and nix-optimise's hardlinking
        # (which catches up right after boot) counts. A one-shot autostart then
        # left the agent dead and every ssh, deploy probes included, keyless.
        # The system profile path, so a switch that bumps 1Password restarts
        # onto the new build instead of the stale one.
        systemd.user.services.onepassword = {
          Unit = {
            Description = "1Password (desktop app and SSH agent)";
            PartOf = ["graphical-session.target"];
            After = ["graphical-session.target"];
          };
          Service = {
            ExecStart = "/run/current-system/sw/bin/1password --silent";
            Restart = "always";
            RestartSec = 2;
          };
          Install.WantedBy = ["graphical-session.target"];
        };

        # On poweroff/reboot the session scope (the compositor) stops before
        # user@.service, so onepassword.service's stop always comes too late:
        # 1Password loses its Wayland socket first, exits 1 without its own
        # shutdown path, and the next start pops "1Password quit unexpectedly".
        # No unit ordering can get ahead of the scope, so hold a logind delay
        # lock and SIGTERM it (a clean exit 0) on PrepareForShutdown instead.
        systemd.user.services.onepassword-quit-before-shutdown = let
          watch = pkgs.writeShellApplication {
            name = "onepassword-quit-before-shutdown";
            runtimeInputs = [pkgs.bash pkgs.glib.bin pkgs.systemd pkgs.gnugrep];
            text = ''
              # A coproc, not a pipeline: a pipeline would also wait on gdbus,
              # which only notices grep is gone on its next signal.
              wait_for() {
                coproc MON { exec gdbus monitor --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1; }
                local pid=$MON_PID
                grep -q -m1 -F "PrepareForShutdown ($1" <&"''${MON[0]}"
                kill "$pid" 2>/dev/null || true
              }
              export -f wait_for
              while true; do
                systemd-inhibit --what=shutdown --mode=delay --who=1Password \
                  --why="Quit 1Password before the compositor goes" \
                  bash -c 'wait_for true && systemctl --user stop onepassword.service'
                # Lock released, shutdown proceeds. Only a cancelled one gets here.
                wait_for false
                systemctl --user start onepassword.service
              done
            '';
          };
        in {
          Unit = {
            Description = "Stop 1Password cleanly before shutdown tears down the session";
            PartOf = ["graphical-session.target"];
            After = ["graphical-session.target"];
          };
          Service = {
            ExecStart = lib.getExe watch;
            Restart = "on-failure";
          };
          Install.WantedBy = ["graphical-session.target"];
        };
      })
    ]);
  };
}

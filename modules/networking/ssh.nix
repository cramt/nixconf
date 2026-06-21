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
          exec = "${pkgs.alacritty}/bin/alacritty -e ${pkgs.zsh}/bin/zsh -c ${value}/bin/ssh_${name}";
        })
      sshTargetPackages;
  in {
    options.myHomeManager.ssh = {
      enable = lib.mkEnableOption "myHomeManager.ssh";
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
          matchBlocks = {
            "*" = {
              controlPath = "~/.ssh/control-%C";
            };
            # Named Host aliases so `herdr --remote luna` (and plain `ssh luna`)
            # resolve. Herdr rides regular SSH like tmux, so a Host entry is all
            # the remote multiplexer needs — no daemon or extra port on luna.
            "luna" = {
              hostname = site.luna_internal_address;
              user = "cramt";
              forwardAgent = true;
            };
            # Same box over WAN (matches the remote_luna helper: public IP, port 2269).
            "luna-remote" = {
              hostname = site.ip;
              port = 2269;
              user = "cramt";
              forwardAgent = true;
            };
          };
        };
        home.packages = (builtins.attrValues sshTargetPackages) ++ (builtins.attrValues sshTargetDesktops);
      }
      (lib.mkIf config.myHomeManager.ssh.use1Password {
        programs.ssh.extraConfig = ''
          Host *
              IdentityAgent ~/.1password/agent.sock
        '';

        xdg.configFile."1Password/ssh/agent.toml" = {
          text = ''
            [[ssh-keys]]
            item = "SSH Key - Personal"
          '';
        };

        xdg.configFile."autostart/1password.desktop".text = ''
          [Desktop Entry]
          Name=1Password
          Exec=1password --silent
          Terminal=false
          Type=Application
          StartupNotify=false
        '';
      })
    ]);
  };
}

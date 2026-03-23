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
    options.myHomeManager.ssh.enable = lib.mkEnableOption "myHomeManager.ssh";
    config = lib.mkIf config.myHomeManager.ssh.enable {
      programs.ssh = {
        enable = true;
        enableDefaultConfig = false;
        extraConfig = ''
          Host *
              IdentityAgent ~/.1password/agent.sock
        '';
        matchBlocks."*" = {
          controlPath = "~/.ssh/control-%C";
        };
      };

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

      home.packages = (builtins.attrValues sshTargetPackages) ++ (builtins.attrValues sshTargetDesktops);
    };
  };
}

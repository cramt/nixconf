{pkgs, ...}: let
  secrets = import ../../secrets.nix;
  sshTargets = {
    luna = "-t cramt@192.168.0.103 -A zellij_smart_start";
    remote_luna = "-t cramt@${secrets.ip} -p 2269 -A zellij_smart_start";
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
  programs.ssh = {
    enable = true;
    addKeysToAgent = "yes";
  };

  home.packages = (builtins.attrValues sshTargetPackages) ++ (builtins.attrValues sshTargetDesktops);
}

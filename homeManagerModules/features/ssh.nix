{ pkgs, ... }:
let
  sshTargets = {
    luna = "cramt@192.168.0.103";
    jump = "ao@161.35.219.109 -A";
    remote_luna = "cramt@84.238.30.251 -p 2269";
  };
  sshTargetPackages = builtins.mapAttrs (name: value: pkgs.writeScriptBin "ssh_${name}" "ssh ${value}") sshTargets;
  sshTargetDesktops = builtins.mapAttrs
    (name: value: pkgs.makeDesktopItem {
      name = "ssh-${name}";
      desktopName = "ssh ${name}";
      exec = "${pkgs.alacritty}/bin/alacritty -e ${pkgs.zsh}/bin/zsh -c ${value}/bin/ssh_${name}";
    })
    sshTargetPackages;
in
{
  programs.ssh = {
    enable = true;
    addKeysToAgent = "yes";
  };

  home.packages = (builtins.attrValues sshTargetPackages) ++ (builtins.attrValues sshTargetDesktops);
}

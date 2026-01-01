{pkgs, config, ...}: let
  secrets = import ../../secrets.nix;
  sshTargets = {
    luna = "-t cramt@${secrets.luna_internal_address} -A";
    remote_luna = "-t cramt@${secrets.ip} -p 2269 -A";
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
    enableDefaultConfig = false;
    matchBlocks."*" = {
      addKeysToAgent = "yes";
      controlPath = "~/.ssh/control-%C";
    };
  };

  # Override SSH_AUTH_SOCK to use GPG agent instead of GNOME keyring
  # (PAM sets it to keyring path, but we disabled the keyring SSH agent)
  home.sessionVariables.SSH_AUTH_SOCK = "\${XDG_RUNTIME_DIR}/gnupg/S.gpg-agent.ssh";

  home.packages = (builtins.attrValues sshTargetPackages) ++ (builtins.attrValues sshTargetDesktops);
}

{ ... }: {
  hmModules.features.zsh = { config, lib, pkgs, ... }: {
    options.myHomeManager.zsh.enable = lib.mkEnableOption "myHomeManager.zsh";
    config = lib.mkIf config.myHomeManager.zsh.enable {
      programs.fzf.enableZshIntegration = true;
      programs.zsh = {
        enable = true;
        dotDir = "${config.xdg.configHome}/zsh";
        shellAliases = {
          ls = "${pkgs.eza}/bin/eza --icons -a --group-directories-first";
          tree = "${pkgs.eza}/bin/eza --color=auto --tree";
          ssh_jump = "ssh ao@161.35.219.109 -A";
          lg = "${pkgs.lazygit}/bin/lazygit";
        };
        enableCompletion = true;
        autosuggestion.enable = true;
        initContent = ''
          export SSH_AUTH_SOCK="$XDG_RUNTIME_DIR/gnupg/S.gpg-agent.ssh"
          export GPG_TTY=$(tty)
          bios_reboot() { systemctl reboot --firmware-setup }
          windows_reboot() { systemctl reboot --boot-loader-entry=auto-windows }
          autoload -Uz edit-command-line
          zle -N edit-command-line
          bindkey '^x^e' edit-command-line
          autoload zmv
        '';
      };
    };
  };
}

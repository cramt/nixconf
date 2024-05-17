{ pkgs, config, ... }: {
  config = {
    home.file = {
      ".local/share/zsh/zsh-autosuggestions".source = "${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions";
      ".local/share/zsh/zsh-fast-syntax-highlighting".source = "${pkgs.zsh-fast-syntax-highlighting}/share/zsh/site-functions";
      ".local/share/zsh/nix-zsh-completions".source = "${pkgs.nix-zsh-completions}/share/zsh/plugins/nix";
      ".local/share/zsh/zsh-vi-mode".source = "${pkgs.zsh-vi-mode}/share/zsh-vi-mode";
    };
    programs.zsh = {
      enable = true;

      shellAliases = {
        ls = "${pkgs.eza}/bin/eza --icons -a --group-directories-first";
        tree = "${pkgs.eza}/bin/eza --color=auto --tree";
        ssh_jump = "ssh ao@161.35.219.109 -A";
      };
      plugins = [
        {
          name = "zsh-syntax-highlighting";
          src = pkgs.zsh-syntax-highlighting;
        }
        {
          name = "zsh-completions";
          src = pkgs.zsh-completions;
        }
        {
          name = "zsh-vi-mode";
          src = pkgs.zsh-vi-mode;
        }
        {
          name = "zsh-autosuggestions";
          src = pkgs.zsh-autosuggestions;
        }
      ];
      oh-my-zsh.enable = true;
      syntaxHighlighting.enable = true;
      initExtra = ''
        if [[ -z "''${SSH_AGENT_PID}" ]]
        then
          eval `ssh-agent -s` > /dev/null
        fi

        ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#${config.colorScheme.colors.base03}"

        bios_reboot() {
          systemctl reboot --firmware-setup
        }

        windows_reboot() {
          systemctl reboot --boot-loader-entry=auto-windows
        }
      '';
    };
  };
}

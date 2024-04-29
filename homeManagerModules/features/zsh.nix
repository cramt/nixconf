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
      };
      initExtra = ''
        if [[ -z "''${SSH_AGENT_PID}" ]]
        then
          eval `ssh-agent -s` > /dev/null
        fi

        # PLUGINS (whatever)
        [ -f "$HOME/.local/share/zsh/zsh-vi-mode/zsh-vi-mode.plugin.zsh" ] && \
        source "$HOME/.local/share/zsh/zsh-vi-mode/zsh-vi-mode.plugin.zsh"

        [ -f "$HOME/.local/share/zsh/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh" ] && \
        source "$HOME/.local/share/zsh/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"

        ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#${config.colorScheme.colors.base03}"
        bindkey '^ ' autosuggest-accept

        [ -f "$HOME/.local/share/zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" ] && \
        source "$HOME/.local/share/zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"

        [ -f "$HOME/.local/share/zsh/nix-zsh-completions/nix.plugin.zsh" ] && \
        source "$HOME/.local/share/zsh/nix-zsh-completions/nix.plugin.zsh"

        bios_reboot() {
          systemctl reboot --firmware-setup
        }
      '';
    };
  };
}

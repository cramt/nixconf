{ pkgs, lib, config, ... }: {
  config = {
    programs.zsh = {
      enable = true;
      shellAliases = {
        ls = "${pkgs.eza}/bin/eza --icons -a --group-directories-first";
        tree = "${pkgs.eza}/bin/eza --color=auto --tree";
        ssh_jump = "ssh ao@161.35.219.109 -A";
      };
      plugins = lib.attrsets.mapAttrsToList
        (name: value: {
          name = name;
          src = value.pkgs or pkgs.${name};
          file = value.file or "";
        })
        {
          "zsh-syntax-highlighting" = {
            file = "share/zsh/site-functions";
          };
          "zsh-completions" = {
            pkgs = pkgs.nix-zsh-completions;
            file = "share/zsh/plugins/nix";
          };
          "zsh-vi-mode" = {
            file = "share/zsh-vi-mode/zsh-vi-mode.plugin.zsh";
          };
          "zsh-history-substring-search" = {
            file = "share/zsh-history-substring-search/zsh-history-substring-search.zsh";
          };
        };
      autosuggestion.enable = true;
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

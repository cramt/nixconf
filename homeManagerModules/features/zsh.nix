{pkgs, ...}: {
  config = {
    programs.zsh = {
      enable = true;

      shellAliases = {
        ls = "${pkgs.eza}/bin/eza --icons -a --group-directories-first";
        tree = "${pkgs.eza}/bin/eza --color=auto --tree";
        ssh_jump = "ssh ao@161.35.219.109 -A";
        lg = "${pkgs.lazygit}/bin/lazygit";
      };
      enableCompletion = true;
      autosuggestion.enable = true;

      initExtra = ''
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

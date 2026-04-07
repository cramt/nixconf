# NixOS graphical bundle — PipeWire, fonts, flatpak, peripheral support
{ ... }: {
  flake.nixosModules."bundles.graphical" = { config, lib, pkgs, ... }: {
    options.myNixOS.bundles.graphical.enable = lib.mkEnableOption "myNixOS.bundles.graphical";
    config = lib.mkIf config.myNixOS.bundles.graphical.enable {
      security.rtkit.enable = true;
      xdg.portal.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
        jack.enable = true;
        wireplumber = {
          enable = true;
          extraConfig."bluetooth-codec" = {
            "monitor.bluez.rules" = [
              {
                matches = [ { "device.name" = "~bluez_card.*"; } ];
                actions.update-props = {
                  "bluez5.codecs" = [ "aac" "sbc_xq" "sbc" ];
                };
              }
            ];
          };
        };
        systemWide = true;
      };
      boot.plymouth.enable = false;
      myNixOS.services.udisks.enable = true;
      services = {
        pulseaudio.enable = false;
        flatpak.enable = true;
      };
      myNixOS = {
        keymapp.enable = true;
        external-monitor-control.enable = true;
      };
      fonts = {
        packages = with pkgs; [
          nerd-fonts.iosevka
          cm_unicode
          corefonts
          noto-fonts
          noto-fonts-cjk-sans
          noto-fonts-color-emoji
          font-awesome
          source-han-sans
          source-han-serif
          ubuntu-classic
          powerline-fonts
          powerline-symbols
          corefonts
        ];
        enableDefaultPackages = true;
      };
    };
  };
}

{ pkgs
, lib
, ...
}: {
  time.timeZone = "Europe/Copenhagen";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_GB.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "da_DK.UTF-8";
    LC_IDENTIFICATION = "da_DK.UTF-8";
    LC_MEASUREMENT = "da_DK.UTF-8";
    LC_MONETARY = "da_DK.UTF-8";
    LC_NAME = "da_DK.UTF-8";
    LC_NUMERIC = "da_DK.UTF-8";
    LC_PAPER = "da_DK.UTF-8";
    LC_TELEPHONE = "da_DK.UTF-8";
    LC_TIME = "da_DK.UTF-8";
  };

  # Enable sound with pipewire.
  sound.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };
  hardware.pulseaudio.enable = false;

  fonts = {
    packages = with pkgs; [
      nerdfonts
      cm_unicode
      corefonts
      noto-fonts
      noto-fonts-cjk
      noto-fonts-emoji
      font-awesome
      source-han-sans
      source-han-sans-japanese
      source-han-serif-japanese
      ubuntu_font_family
      powerline-fonts
      powerline-symbols

    ];
    fontconfig = {
      defaultFonts = {
        sansSerif = [ "Nerd Font" ];
        serif = [ "Nerd Font" ];
        monospace = [ "Nerd Font Mono" ];
      };
    };

    enableDefaultPackages = true;
  };

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };
  # battery
  services.upower.enable = true;
}

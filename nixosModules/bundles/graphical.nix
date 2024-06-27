{ pkgs
, inputs
, ...
}:
{
  # Enable sound with pipewire.
  sound.enable = true;
  security.rtkit.enable = true;
  services.pipewire = {
    package = inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.pipewire;
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber = {
      enable = true;
      package = pkgs.wireplumber;
    };
  };
  myNixOS.services.udisks.enable = true;
  hardware.pulseaudio.enable = false;
  fonts = {
    packages = with pkgs;
      [
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
        corefonts
      ];

    enableDefaultPackages = true;
  };
}

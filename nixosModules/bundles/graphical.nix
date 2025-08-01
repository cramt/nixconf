{
  pkgs,
  inputs,
  config,
  ...
}: {
  # Enable sound with pipewire.
  security.rtkit.enable = true;
  xdg.portal = {
    enable = true;
    wlr.enable = true;
  };
  services.pipewire = {
    #package = inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.pipewire;
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    jack.enable = true;
    wireplumber.enable = true;
    systemWide = true;
  };
  boot = {
    plymouth = {
      enable = false;
    };
  };
  myNixOS.services.udisks.enable = true;
  services = {
    pulseaudio.enable = false;
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

{
  pkgs,
  inputs,
  config,
  ...
}: {
  # Enable sound with pipewire.
  security.rtkit.enable = true;
  # Portal configuration is handled by Home Manager for desktop-specific setup
  # (e.g., cosmic/default.nix configures xdg-desktop-portal-cosmic)
  xdg.portal.enable = true;
  services.pipewire = {
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
      beeper
    ];

    enableDefaultPackages = true;
  };
}

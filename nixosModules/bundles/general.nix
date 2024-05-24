{ pkgs
, lib
, ...
}:
let
  stylixAsset = ../../media/cosmere.mp4;
  stylixAssetFirstFrame = pkgs.runCommand "stylix_asset_first_frame" { } ''
    mkdir -p $out
    ${pkgs.ffmpeg}/bin/ffmpeg -i ${stylixAsset} -vf "select=eq(n\,0)" $out/output-%03d.png
    mv $out/output-*.png $out/output.png
  '';
in
{
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
  stylix = {
    polarity = "dark";
    image = "${stylixAssetFirstFrame}/output.png";
    opacity = {
      terminal = 0.8;
      applications = 0.8;
      desktop = 0.5;
      popups = 0.8;
    };
    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Ice";
    };
    fonts = {
      monospace = {
        package = pkgs.iosevka;
        name = "Iosevka Extended";
      };
      sansSerif = {
        package = pkgs.iosevka;
        name = "Iosevka Etoile";
      };
      serif = {
        package = pkgs.iosevka;
        name = "Iosevka Etoile";
      };
    };
  };

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

  environment.sessionVariables = { };
  # battery
  services.upower.enable = true;
}

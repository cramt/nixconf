{ pkgs
, inputs
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
        package = pkgs.iosevka.out;
        name = "Iosevka Nerd Font";
      };
      sansSerif = {
        package = pkgs.open-sans.out;
        name = "Open Sans";
      };
      serif = {
        package = pkgs.open-sans.out;
        name = "Open Sans";
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
}

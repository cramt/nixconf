{ pkgs, ... }:
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


  environment.sessionVariables = { };
  # battery
  services.upower.enable = true;

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
        package = pkgs.inter.out;
        name = "Open Sans";
      };
      serif = {
        package = pkgs.inter.out;
        name = "Open Sans";
      };
    };
  };

  myNixOS = {
    ssh.enable = true;
  };

  nix = {
    optimise.automatic = true;
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };
}

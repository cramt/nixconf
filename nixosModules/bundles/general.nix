{
  pkgs,
  lib,
  config,
  inputs,
  ...
}: let
  cfg = config.myNixOS.bundles.general;
  stylixImage =
    if lib.hasSuffix ".mp4" cfg.stylixAsset
    then let
      stylixAssetFirstFrame = pkgs.runCommand "stylix_asset_first_frame" {} ''
        mkdir -p $out
        ${pkgs.ffmpeg}/bin/ffmpeg -i ${cfg.stylixAsset} -vf "select=eq(n\,0)" $out/output-%03d.png
        mv $out/output-*.png $out/output.png
      '';
    in "${stylixAssetFirstFrame}/output.png"
    else cfg.stylixAsset;
in {
  options.myNixOS.bundles.general = {
    stylixAsset = lib.mkOption {
      type = lib.types.path;
    };
  };
  config = {
    security.pam.services.hyprlock = {};

    nix.nixPath = ["nixpkgs=${inputs.nixpkgs}"];

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
      LC_TIME = "en_GB.UTF-8";
    };

    programs.nh = {
      enable = true;
      clean.enable = true;
      clean.extraArgs = "--keep-since 4d --keep 3";
      flake = "/home/cramt/nixconf";
      #package = inputs.nh.packages.${pkgs.system}.nh;
    };

    environment.sessionVariables = {};
    environment.systemPackages = [pkgs.comma];
    # battery
    services.upower.enable = true;

    services.udev = {
      extraRules = ''
        ENV{ID_VENDOR_ID}=="6969", ENV{ID_MODEL_ID}=="b00b", MODE="7777"
        SUBSYSTEM=="usb", ATTRS{idVendor}=="2e8a", ATTRS{idProduct}=="0003", MODE="0666"
        ACTION=="add|change", SUBSYSTEM=="usb|tty|hidraw", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="27dd", MODE="0666", GROUP="plugdev", TAG+="uaccess"
      '';
      packages = [inputs.probe-rs-rules.packages.${pkgs.stdenv.hostPlatform.system}.default];
    };

    stylix = {
      polarity = "dark";
      image = stylixImage;
      opacity = {
        terminal = 0.8;
        applications = 0.8;
        desktop = 0.5;
        popups = 0.8;
      };
      cursor = {
        package = inputs.nixpkgs-stable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.bibata-cursors;
        name = "Bibata-Modern-Ice";
        size = 32;
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
      fwupd.enable = true;
    };

    systemd.services.nix-daemon.serviceConfig = {
      Nice = 19;
      IOSchedulingClass = "idle";
    };

    nix = {
      optimise.automatic = true;
    };
  };
}

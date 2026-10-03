{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./home-apps.nix
    ./web-apps.nix
    ./kdeconnect.nix
    inputs.emrakul.nixosModules.default
    inputs.disko.nixosModules.default
    (import ./disko.nix {device = "/dev/nvme0n1";})
  ];

  boot = {
    loader.systemd-boot.enable = true;
    # /boot is 1 GiB and each generation here carries a 7.3-rc kernel plus
    # the NVIDIA module initrd; unlimited entries filled it and broke a deploy.
    loader.systemd-boot.configurationLimit = 5;
    loader.efi.canTouchEfiVariables = true;
    # 7.3 is the first kernel whose hid-steam drives the 2026 Steam Controller
    # (Vicki Pfau's series, merged for 7.3-rc1), and the couch compositor reads
    # the controller through that driver rather than through Steam. legacy_580
    # was build-checked against 7.3-rc4. Back to linux_zen once it reaches 7.3.
    # https://lore.kernel.org/linux-input/20260807013334.2109386-1-vi@endrift.com/
    kernelPackages = pkgs.linuxKernel.packages.linux_testing;

    # Kill the internal panel: the lid is always shut, and leaving it enabled
    # means the desktop spans a screen nobody can see and windows can open on
    # it. With it gone the TV is the only display, so anything that starts
    # fullscreen lands where it should without per-app placement rules.
    # consoleblank=0: the VT blanks itself after 10 minutes by default, which
    # is a black TV on any boot that drops to a console or takes a while to
    # reach the session.
    kernelParams = ["video=eDP-1:d" "consoleblank=0"];
  };

  # No fbdev console on the NVIDIA card. Its modeset to 4K at boot lands ~2 s
  # before emrakul's own, and the LG gets stuck on "No signal" trying to
  # lock onto both (https://github.com/cramt/emrakul/issues/25). Without it
  # emrakul's modeset is the only one; recovery is over ssh. Drop this if
  # emrakul learns to survive a preceding modeset.
  hardware.nvidia.moduleParams.nvidia-drm.fbdev = lib.mkForce 0;

  security.polkit.enable = true;

  # emrakul is the only session: it boots straight onto the TV on tty1 and
  # restarts itself if it dies. The other VTs keep their gettys as a way in
  # from a keyboard, and sshd stays on below.
  services.emrakul = {
    enable = true;
    user = "cramt";
    settings = {
      device = "/dev/dri/by-path/pci-0000:01:00.0-card";
      connector = "HDMI-A-1";
      mode = "3840x2160@60";
      # Web apps lay out at 1920x1080 and draw at 4K: readable from the couch.
      scale = 2;
      # The LG's own settings, held to what's on screen over its network API
      # and put back whenever they drift (emrakul's src/tv.rs).
      tv = {
        host = "192.168.178.36";
        key_file = config.services.onepassword-secrets.secretPaths.tvClientKey;
        # Not a secret: it pins the TV's self-signed cert, so nobody else on
        # the LAN can pose as the TV and collect the key.
        cert_fingerprint = "11:C5:B1:C5:90:77:50:AB:B9:DA:2A:66:65:CC:CE:2B:B2:88:A5:83:F4:5A:33:39:E7:1F:87:BF:2F:80:85:52";
        input = "HDMI_1";
        settings = {
          # Overscan clipped Home's edges and Chromium's top bar.
          aspectRatio = {
            justScan = "on";
            arcPerApp = "original";
          };
          # "auto" dims the panel with the picture, which is what made dark
          # scenes unwatchable. It isn't per picture mode, so it lives here.
          picture.energySaving = "off";
        };
        # Home and web apps share a mode, so going Home never switches it.
        home.picture.pictureMode = "filmMaker";
        app.picture.pictureMode = "filmMaker";
        # Game Optimizer, for Game entries (X-Emrakul-Tv=game).
        profiles.game.picture.pictureMode = "game";
      };
    };
  };

  # Just the TV's SSAP client key, not the opnix-secrets bundle: none of the
  # homelab's other secrets belong on the TV box. Needs /etc/opnix-token on
  # ganymede. emrakul reads the key on every connect, so no restart wiring.
  services.onepassword-secrets = {
    enable = true;
    tokenFile = "/etc/opnix-token";
    secrets.tvClientKey = {
      reference = "op://Homelab/LG-TV/password";
      owner = "cramt";
      mode = "0400";
    };
  };

  # Plasma used to bring PipeWire along; with emrakul nothing else does.
  # It runs per user, socket-activated in the user manager that emrakul's PAM
  # login session starts, so it comes up when a web app first plays sound.
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    # Sound follows the picture. The 1050 Ti's HDMI audio ships with session
    # priority 696 against the internal ALC255's 1009, so without this
    # everything plays out of the laptop speakers with the lid shut. The node
    # name embeds the PCI address, so it's stable across boots.
    wireplumber.extraConfig."51-hdmi-default-sink"."monitor.alsa.rules" = [
      {
        matches = [{"node.name" = "alsa_output.pci-0000_01_00.1.hdmi-stereo";}];
        actions.update-props."priority.session" = 2000;
      }
    ];
  };

  myNixOS = {
    nvidia = {
      enable = true;
      # GTX 1050 Ti (GP107M, Pascal). NVIDIA dropped Maxwell/Pascal/Volta after
      # the 580 branch, so `stable` (595.x) builds and deploys fine here and
      # then can't bind the card — a dead TV, not an obvious driver error.
      # Remove this pin only if the card is replaced with Turing or newer.
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    };
    bundles.general.stylixAsset = ../../media/artemis2_1.jpg;
    bundles.general.enable = true;
    bundles.users.enable = true;

    # The Claude session on luna gets in here (and only here) to drive the
    # couch-compositor bring-up over SSH. Setting home-users at all replaces
    # the option's default attrset, so userConfig has to be restated too.
    # Drop the extra key once that work no longer needs hands on the box.
    home-users.cramt = {
      userConfig = ./home.nix;
      authorizedKeys =
        (import ../../myLib/keys.nix).alex
        ++ ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMHteAL112dycYVBLCRppKjK7+cgRIXrXMwV3jHHojrH solemn-simulacrum@luna"];
    };

    services = {
      sshd.enable = true;
    };
  };

  # Never sleep, even on lid close
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
    HandleSuspendKey = "ignore";
    HandleHibernateKey = "ignore";
    IdleAction = "ignore";
  };
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowSuspendThenHibernate = "no";
    AllowHybridSleep = "no";
  };

  networking.networkmanager.enable = true;

  services.xserver = {
    xkb = {
      variant = "nodeadkeys";
      layout = "dk";
    };
  };

  console.keyMap = "dk-latin1";

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
  };

  environment.systemPackages = [
    pkgs.ghostty.terminfo
  ];

  system.stateVersion = "26.05";
}

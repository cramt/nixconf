{ inputs, lib, pkgs, config, ... }:
let
  steamlink = pkgs.callPackage ../../packages/steamlink {};

  # Kodi is the couch shell. The GBM build renders straight on KMS/DRM (no X,
  # no Wayland) — the same direct-to-framebuffer path the old Steam Link kiosk
  # used, but it takes the DRM master via logind so it cooperates with greetd's
  # seat. Bundle the client addons we want available out of the box.
  kodiPkg = pkgs.kodi-gbm.withPackages (p: with p; [
    jellycon              # Jellyfin client
    youtube               # YouTube
    inputstream-adaptive  # adaptive (DASH/HLS) streams youtube et al. rely on
    inputstreamhelper
  ]);

  # Single-KMS-app session model. Only one fullscreen app may own the DRM
  # master at a time, and Kodi-on-GBM does not reliably hand KMS to a nested
  # eglfs child — so rather than launch the streamers *inside* Kodi we switch
  # the whole greetd session. eros-shell reruns on every session exit; a marker
  # file picks the next app and defaults back to Kodi, so quitting Steam Link or
  # Moonlight drops you back on the Kodi home screen. A Kodi/streamer crash also
  # just re-enters eros-shell (empty marker → Kodi), so the TV never strands.
  sessionMarker = "/tmp/eros-session-next";

  # Qt eglfs-on-KMS env shared by the Qt streamers (Steam Link, Moonlight).
  qtKmsEnv = ''
    export QT_QPA_PLATFORM=eglfs
    export QT_QPA_EGLFS_INTEGRATION=eglfs_kms
    export QT_QPA_EGLFS_KMS_ATOMIC=1
    export QT_QPA_EGLFS_HIDECURSOR=1
  '';

  erosShell = pkgs.writeShellScript "eros-shell" ''
    target=kodi
    if [ -r ${sessionMarker} ]; then
      target=$(${pkgs.coreutils}/bin/cat ${sessionMarker})
      ${pkgs.coreutils}/bin/rm -f ${sessionMarker}
    fi
    case "$target" in
      steamlink)
        ${qtKmsEnv}
        exec ${steamlink}/bin/steamlink
        ;;
      moonlight)
        ${qtKmsEnv}
        exec ${pkgs.moonlight-qt}/bin/moonlight
        ;;
      *)
        exec ${kodiPkg}/bin/kodi
        ;;
    esac
  '';

  # One no-arg launcher per streamer, invoked from a Kodi favourite via
  # System.Exec: record which app to run next, then SIGTERM Kodi (the GBM binary
  # is `kodi.bin`, which shuts down cleanly) so greetd reruns eros-shell into it.
  mkLaunch = app: pkgs.writeShellScript "eros-launch-${app}" ''
    ${pkgs.coreutils}/bin/echo "${app}" > ${sessionMarker}
    ${pkgs.procps}/bin/pkill -TERM -x kodi.bin || true
  '';
  launchSteamlink = mkLaunch "steamlink";
  launchMoonlight = mkLaunch "moonlight";

  # Shipped to ~/.kodi/userdata so the streamers appear under Kodi's Favourites,
  # navigable with the controller.
  kodiFavourites = pkgs.writeText "favourites.xml" ''
    <favourites>
      <favourite name="Steam Link">System.Exec("${launchSteamlink}")</favourite>
      <favourite name="Moonlight">System.Exec("${launchMoonlight}")</favourite>
    </favourites>
  '';
in
{
  imports = [
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.display-vc4
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.bluetooth
    inputs.nixos-raspberrypi.nixosModules.sd-image
  ];

  config = {
    # nixos-raspberrypi modules expect their own flake passed as a module arg
    # (used to pull rpi-specific kernel/firmware packages). Wire it up since
    # we go through our own myLib.mkSystem rather than their lib.nixosSystem.
    _module.args.nixos-raspberrypi = inputs.nixos-raspberrypi;

    nix.settings = {
      trusted-users = [ "cramt" ];

      substituters = [
        "https://nix-community.cachix.org"
        "https://nixos-raspberrypi.cachix.org"
      ];
      trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      ];
    };

    myNixOS = {
      services.sshd.enable = true;
    };

    # nixosModules.default ships stylix/lix/zfs/quadlet by default. None has
    # cached aarch64 builds for nvmd's nixpkgs pin — switch off to keep
    # cache-only. quadlet auto-enables when its enable option is null, which
    # transitively pulls podman + matplotlib at build time; force off explicitly.
    stylix.enable = lib.mkForce false;
    nix.package = lib.mkForce pkgs.nix;
    boot.supportedFilesystems.zfs = lib.mkForce false;
    virtualisation.quadlet.enable = false;

    nixpkgs = {
      hostPlatform = "aarch64-linux";
      config = {
        allowUnfree = true;
      };
      # nixos-raspberrypi modules reference `pkgs.raspberrypi-utils` and friends
      # that only exist after their overlays are applied. Pulling them in lets
      # the rpi modules resolve their own deps without forking nixpkgs.
      overlays = [
        inputs.nixos-raspberrypi.overlays.pkgs
        inputs.nixos-raspberrypi.overlays.vendor-pkgs
        inputs.nixos-raspberrypi.overlays.vendor-firmware
        inputs.nixos-raspberrypi.overlays.vendor-kernel
        inputs.nixos-raspberrypi.overlays.kernel-and-firmware
        inputs.nixos-raspberrypi.overlays.bootloader
      ];
    };

    # Use the firmware-loads-kernel-directly path instead of u-boot. nixos-
    # raspberrypi defaults to u-boot which references a nixpkgs attribute
    # (`ubootRaspberryPi_64bit`) that's been split into `ubootRaspberryPi4_64bit`
    # in unstable. The "kernel" bootloader avoids u-boot entirely and is faster.
    boot.loader.raspberry-pi.bootloader = "kernel";

    # config.txt firmware tweaks from the modcommunity Steam Link guide.
    # FKMS (vc4-fkms-v3d) was removed from RPi firmware around 2023 — modern
    # boards only ship KMS (the default in nixos-raspberrypi). The historical
    # FKMS-only requirement was a Buster-era constraint; current Steam Link
    # builds run fine on KMS.
    hardware.raspberry-pi.config.all.options = {
      # Wake the HDMI link even when the TV is off / EDID drops at boot.
      hdmi_force_hotplug = { enable = true; value = 1; };
      # Force HDMI mode (vs DVI) so audio is carried over the cable.
      hdmi_drive = { enable = true; value = 2; };
      # Boost HDMI signal level to survive long / cheap cables.
      config_hdmi_boost = { enable = true; value = 4; };
      # Bigger CMA window so the GPU has room for video decode buffers.
      gpu_mem = { enable = true; value = 256; };
    };

    # swiotlb: the Pi 4's BCM2711 can only DMA-address the lower 1 GiB of RAM,
    # so VC4 bounces framebuffers through swiotlb. A 4K BGRA framebuffer is
    # ~32 MiB and overruns the pool (kernel logs `vc4-drm gpu: swiotlb buffer is
    # full`, Steam Link then freezes and crashes the moment a stream starts);
    # the modest resolutions forced below fit comfortably.
    #
    # video=...e: the display is an LG 4K TV (EDID manufacturer GSM, name
    # "LG TV SSCR2"; native timing 3840x2160@30). We deliberately force 1080p
    # rather than the native 4K — a 4K framebuffer is ~33 MiB and overruns the
    # swiotlb pool above, and the TV upscales 1080p fine (Steam Link streams
    # 1080p regardless). The trailing `e` ("output forced on") is the full-KMS
    # equivalent of the legacy config.txt `hdmi_force_hotplug=1` (which
    # vc4-kms-v3d + disable_fw_kms_setup ignore). It matters on a TV: TVs drop
    # HPD/EDID when powered off or on another input, and without `e` a boot
    # while the TV is off leaves the connector disconnected → vc4 builds no CRTC
    # (`Cannot find any crtc or sizes`) → Steam Link's eglfs_kms backend crashes
    # for want of an output, staying blank even once the TV comes back. Forcing
    # the connector pins it to 1080p regardless of HPD state. Steam Link renders
    # on HDMI-A-1 (eglfs picks the first forced connector); both ports are
    # forced so the cable works in either socket.
    boot.kernelParams = [
      "swiotlb=131072"
      "video=HDMI-A-1:1920x1080@60e"
      "video=HDMI-A-2:1920x1080@60e"
    ];

    # Steam Link wants /dev/uinput for virtual controller emulation, and xpadneo
    # gives proper Xbox controller (rumble, battery) support over Bluetooth.
    boot.kernelModules = [ "uinput" ];
    boot.extraModulePackages = [ config.boot.kernelPackages.xpadneo ];

    networking = {
      hostName = "eros";
      useNetworkd = true;
    };

    systemd = {
      network = {
        enable = true;

        networks."10-lan" = {
          matchConfig.Name = "end0";
          networkConfig.DHCP = "yes";
          linkConfig.RequiredForOnline = "routable";
        };
      };
    };

    users.users.cramt = {
      isNormalUser = true;
      extraGroups = [ "wheel" "video" "render" "input" "audio" "plugdev" ];
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwaPHqAJyayzLGfkEhwoDskUUyTr0aEovcc1Nzg2zXH alex.cramt@gmail.com"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I alex.cramt@gmail.com"
      ];
    };

    users.groups.plugdev = {};

    security.sudo.wheelNeedsPassword = false;

    environment.systemPackages = with pkgs; [
      libraspberrypi
      raspberrypi-eeprom
      neovim
      btop
      steamlink
      moonlight-qt
      kodiPkg        # the addon-bundled GBM build; also puts kodi-send on PATH
    ];

    # Audio: pipewire over HDMI. Steam Link's bundled SDL3 talks to PulseAudio,
    # which pipewire-pulse provides.
    services.pulseaudio.enable = false;
    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = false;
      pulse.enable = true;
    };

    # Steam Link's controller udev rules + uinput module-load fragment ship from
    # the package so changes track upstream.
    services.udev.packages = [ steamlink ];

    # Steam Controller (the 2.4 GHz USB dongle). steam-hardware ships the udev
    # rules; the kernel hid-steam driver exposes it as a standard gamepad and
    # emulates keyboard/mouse ("lizard mode") so it can drive Kodi's UI, while
    # Steam Link and Moonlight see it as a controller directly.
    hardware.steam-hardware.enable = true;

    # Boot into the Kodi couch shell via greetd; eros-shell is the session
    # dispatcher (see the let-binding above) that also lets Kodi favourites
    # switch the session into Steam Link or Moonlight and back.
    services.greetd = {
      enable = true;
      settings = {
        initial_session = {
          command = toString erosShell;
          user = "cramt";
        };
        default_session = {
          command = toString erosShell;
          user = "cramt";
        };
      };
    };

    # Ship the Favourites menu (Steam Link / Moonlight launchers) into Kodi's
    # userdata. tmpfiles creates the dirs so the symlink lands before Kodi's
    # first run; the target is read-only in the store, which is fine for a kiosk.
    systemd.tmpfiles.rules = [
      "d /home/cramt/.kodi 0755 cramt users - -"
      "d /home/cramt/.kodi/userdata 0755 cramt users - -"
      "L+ /home/cramt/.kodi/userdata/favourites.xml - - - - ${kodiFavourites}"
    ];

    services.dbus.enable = true;

    hardware.enableRedistributableFirmware = true;

    # eros tracks nixos-raspberrypi's nixos-unstable branch (release 26.11),
    # whose nixpkgs has services.kmscon.config / services.displayManager.generic,
    # so stylix's targets merge without stubs.
    system.stateVersion = "26.11";
  };
}

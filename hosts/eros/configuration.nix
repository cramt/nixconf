{ inputs, lib, pkgs, config, ... }:
let
  # Steam Link (patched, aarch64). Kept here for its udev rules + uinput
  # fragment; the launcher itself runs the copy home-manager installs.
  steamlink = pkgs.callPackage ../../packages/steamlink {};
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
    # swiotlb pool above, and the TV upscales 1080p fine. The trailing `e`
    # ("output forced on") is the full-KMS equivalent of the legacy config.txt
    # `hdmi_force_hotplug=1`: TVs drop HPD/EDID when powered off or on another
    # input, and without `e` a boot while the TV is off leaves the connector
    # disconnected -> vc4 builds no CRTC (`Cannot find any crtc or sizes`) -> the
    # eglfs/Wayland backend crashes for want of an output, staying blank even
    # once the TV comes back. Forcing the connector pins it to 1080p regardless
    # of HPD state.
    #
    # Only HDMI-A-1 (the port the TV is actually on — EDID confirms "LG TV
    # SSCR2") is forced. Forcing HDMI-A-2 as well manufactured a *phantom*
    # second output on the empty socket: `e` builds a CRTC there with no display
    # attached, sway then made that dead output the focused one, and the wofi
    # launcher opened on it — invisible on the TV (swaybg paints the wallpaper on
    # every output, so the TV still showed the background, which masked it). One
    # forced port = one output = the menu always lands on the TV. If the cable
    # ever moves to the other socket, switch this line to HDMI-A-2.
    boot.kernelParams = [
      "swiotlb=131072"
      "video=HDMI-A-1:1920x1080@60e"
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

    # eros is a lean, cache-only rpi host, so it does NOT use the bundles.users
    # multi-user machinery (that assigns groups eros lacks — docker/gamemode/
    # libvirtd — and drags in a heavy HM baseline). The user + home-manager are
    # wired directly below instead.
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

    # Minimal home-manager wiring. useGlobalPkgs makes HM inherit the system's
    # aarch64 pkgs (with the rpi overlays) rather than instantiating its own
    # nixpkgs; useUserPackages installs into /etc/profiles. The couch shell
    # (sway + wofi launcher) lives entirely in ./home.nix.
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      # Back up (don't clobber) any pre-existing dotfile that collides with an
      # HM-managed one. Without this, HM activation hard-fails at
      # checkLinkTargets on the FIRST collision and writes NONE of its files —
      # so a stray ~/.config/mozilla/firefox/profiles.ini (left by a manual
      # Firefox run before first deploy) aborts the whole activation, leaving
      # ~/.config/sway/config unwritten and sway falling back to its stock
      # default config (blue wallpaper + bar, no couch shell). Backing up keeps
      # deploys/reflashes idempotent against leftover state.
      backupFileExtension = "hm-bak";
      users.cramt = import ./home.nix;
      # desktop.niri (imported unconditionally by mkSystem, like every nixos
      # module) makes niri-flake inject its HM module into sharedModules for all
      # users. That module carries a stylix→niri target reading config.stylix.
      # enable, which is undeclared in HM here because eros runs stylix disabled
      # (so stylix never injects its HM options). eros's couch shell uses none of
      # those shared modules, so clear them.
      sharedModules = lib.mkForce [ ];
    };

    environment.systemPackages = with pkgs; [
      libraspberrypi
      raspberrypi-eeprom
      neovim
      btop
      # sway's `output * bg <img>` shells out to swaybg; it isn't in
      # programs.sway's default helper set, so without it the image bg silently
      # no-ops to a black screen. In systemPackages (not just home.packages) so
      # it's on the greetd-launched session's PATH.
      swaybg
    ];

    # Emoji + base fonts for the wofi launcher glyphs.
    fonts = {
      enableDefaultPackages = true;
      packages = with pkgs; [ noto-fonts noto-fonts-color-emoji ];
    };

    # Audio: pipewire over HDMI. Steam Link's bundled SDL talks to PulseAudio,
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

    # Steam Controller. steam-hardware ships the udev rules (also covers the
    # 2.4 GHz dongle if it ever moves here). eros uses the controller over
    # Bluetooth, where it presents as a HID mouse+keyboard ("lizard mode") — the
    # couch-shell launcher is driven entirely by that (trackpad->mouse, d-pad->
    # arrows, A->enter), and Steam Link promotes it to a real gamepad for
    # streamed sessions. No sc-controller needed.
    hardware.steam-hardware.enable = true;
    hardware.bluetooth.enable = true;

    # Re-seed the controller's Bluetooth bond from 1Password so the pairing
    # survives SD-card reflashes (BlueZ bonds live on the SD card otherwise).
    myNixOS.declarativeBluetooth = {
      enable = true;
      devices.steamController = {
        adapter = "DC:A6:32:0B:27:48";   # eros onboard radio (stable across reflash)
        address = "F8:FC:54:D5:6A:06";   # controller bond/identity address
        secretRef = "op://Homelab/SteamControllerBond/info";
      };
    };

    # sway is the persistent couch shell. programs.sway gives the wrapped
    # package + dbus + polkit; greetd launches it and it never exits (the wofi
    # supervisor loop in home.nix keeps the session alive).
    programs.sway.enable = true;

    # Drop the XDG desktop portals programs.sway would pull in: xdg-desktop-
    # portal 1.20.4 fails its own test suite on this rpi nixpkgs pin
    # (test_dynamiclauncher + test_notification), which breaks the eros build
    # natively AND blocks the x86 flash-eros cross-build (uncached aarch64
    # portal). Kept force-off from v1 to preserve buildability.
    #
    # NOTE: if the Firefox-kiosk crash turns out to be portal-related, the fix
    # is to re-enable portals with the failing tests skipped via an overlay
    # (`xdg-desktop-portal.overrideAttrs (_: { doCheck = false; })`) rather than
    # nuking them — confirm from /tmp logs on eros first.
    xdg.portal.enable = lib.mkForce false;

    # Boot straight into sway via greetd. greetd exits whenever its session
    # command exits, so it simply relaunches sway on any crash/quit — the TV is
    # never stranded. App switching happens inside sway (the wofi loop), so
    # there's no greetd churn and none of v1's Kodi kill-dance.
    services.greetd = {
      enable = true;
      settings =
        let session = { command = "${config.programs.sway.package}/bin/sway"; user = "cramt"; };
        in {
          initial_session = session;
          default_session = session;
        };
    };

    # greetd launches the system sway, which reads ~/.config/sway/config written
    # by HM activation. Order greetd after that unit so a fresh-reflash boot
    # can't start sway before its config exists (which would drop it to the stock
    # default config with no couch shell). home-manager-cramt.service is a
    # oneshot RemainAfterExit unit, so `after` waits for it to finish.
    systemd.services.greetd = {
      after = [ "home-manager-cramt.service" ];
      wants = [ "home-manager-cramt.service" ];
    };

    services.dbus.enable = true;

    hardware.enableRedistributableFirmware = true;

    # eros tracks nixos-raspberrypi's nixos-unstable branch (release 26.11).
    system.stateVersion = "26.11";
  };
}

# NixOS graphical bundle — PipeWire, fonts, peripheral support
{ ... }: {
  flake.nixosModules."bundles.graphical" = { config, lib, pkgs, ... }: {
    options.myNixOS.bundles.graphical.enable = lib.mkEnableOption "myNixOS.bundles.graphical";
    config = lib.mkIf config.myNixOS.bundles.graphical.enable {
      security.rtkit.enable = true;
      xdg.portal.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
        jack.enable = true;
        wireplumber = {
          enable = true;
          extraConfig."bluetooth-codec" = {
            # The codec list has to be a *monitor* property, not a per-device
            # rule: enumerate-device.lua builds the bluez monitor from
            # monitor.bluez.properties, and that is what registers the A2DP
            # endpoints with bluetoothd. A monitor.bluez.rules update-props
            # only decorates the device object afterwards, long after the
            # headset has already negotiated a codec against the full endpoint
            # set. Left as a rule, LDAC still got offered, the WH-1000XM4 chose
            # it, the transport failed ("media codec switch: failed
            # (org.bluez.Error.Failed)"), and the card fell back to profile
            # "off" — which persists to WirePlumber's state store, so the
            # headset shows as connected with no output device forever after.
            "monitor.bluez.properties" = {
              "bluez5.codecs" = [ "aac" "sbc_xq" "sbc" ];
            };
            "monitor.bluez.rules" = [
              {
                matches = [ { "device.name" = "~bluez_card.*"; } ];
                actions.update-props = {
                  # Don't auto-switch to HFP/HSP when an app opens the mic.
                  # The WH-1000XM4 drops the link on the A2DP->HFP transition,
                  # causing random disconnect/reconnect cycles.
                  "bluez5.autoswitch-profile" = false;
                };
              }
            ];
          };
        };
        systemWide = true;
      };
      boot.plymouth.enable = false;
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
          noto-fonts-color-emoji
          font-awesome
          source-han-sans
          source-han-serif
          ubuntu-classic
          powerline-fonts
          powerline-symbols
          corefonts
        ];
        enableDefaultPackages = true;
      };
    };
  };
}

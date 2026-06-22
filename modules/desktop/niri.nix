# Niri scrollable-tiling Wayland compositor (system side).
#
# inputs.niri-flake.nixosModules.niri carries the heavy lifting when
# programs.niri.enable is set: it registers the session with the display
# manager (services.displayManager.sessionPackages), wires xdg-desktop-portal
# (gnome for screencast + niri's own config), enables polkit + a polkit-kde
# agent user service, gnome-keyring, the swaylock PAM service, and adds the
# niri.cachix substituter (niri-flake.cache.enable, default true).
#
# The companion user shell (noctalia) and the actual niri config/keybinds live
# in the Home Manager feature (modules/hm-features/niri.nix → myHomeManager.niri).
{ inputs, ... }: {
  flake.nixosModules."desktop.niri" = { config, lib, pkgs, ... }: let
    cfg = config.myNixOS.niri;
  in {
    imports = [ inputs.niri-flake.nixosModules.niri ];

    options.myNixOS.niri.enable = lib.mkEnableOption "myNixOS.niri";

    config = lib.mkIf cfg.enable {
      programs.niri = {
        enable = true;
        # v25.08; pairs with xwayland-satellite-stable for integrated XWayland.
        package = pkgs.niri-stable;
      };

      # Route the Settings portal interface to the gtk backend. niri-flake's
      # default niri-portals.conf prefers the gnome backend (default=gnome;gtk),
      # whose org.freedesktop.impl.portal.Settings.Read takes ~1s per call;
      # GTK apps read portal settings several times during startup, so this
      # added ~5s to every GTK launch (e.g. ghostty on Super+T). The gtk
      # backend answers the same reads in ~10ms with identical values.
      # Setting xdg.portal.config.niri writes /etc/xdg-desktop-portal/
      # niri-portals.conf, which fully replaces the package file (portal
      # configs are not merged across dirs), so the other backend routes from
      # niri-flake's config are replicated here. gnome stays the default for
      # everything else (screencast still needs it).
      xdg.portal.config.niri = {
        default = [ "gnome" "gtk" ];
        "org.freedesktop.impl.portal.Access" = "gtk";
        "org.freedesktop.impl.portal.Notification" = "gtk";
        "org.freedesktop.impl.portal.Secret" = "gnome-keyring";
        "org.freedesktop.impl.portal.Settings" = "gtk";
      };
    };
  };
}

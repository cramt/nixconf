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
    };
  };
}

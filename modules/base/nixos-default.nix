# NixOS base configuration — imported as nixosModules.default
# Provides core nix settings, overlays, and imports shared modules
{ inputs, ... }: {
  flake.nixosModules.default = { config, lib, pkgs, ... }: {
    imports = [
      inputs.home-manager.nixosModules.home-manager
      inputs.stylix.nixosModules.stylix
      inputs.foundryvtt.nixosModules.foundryvtt
      inputs.nixarr.nixosModules.default
      inputs.jellarr.nixosModules.default
      inputs.quadlet-nix.nixosModules.quadlet
      ./portselector.nix
    ];

    config = {
      systemd.user.settings.Manager.DefaultEnvironment = ''"PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"'';
      stylix.enable = true;
      services.gnome.gcr-ssh-agent.enable = false;
      # mkDefault, because this lands on every host including the small ARM ones
      # (eros, mercury) that have no cached aarch64 lix and shouldn't compile a
      # nix implementation to boot. Those set `nix.package = pkgs.nix;` plainly;
      # without mkDefault here that's an option conflict and they'd each need a
      # mkForce to say something this ordinary.
      nix.package = lib.mkDefault pkgs.lix;

      # quadlet-nix auto-enables when this is left null (its default), which
      # pulls podman — and transitively matplotlib — into the build of hosts that
      # never mentioned containers. Nothing in this repo uses quadlet today, so
      # off unless a host asks; mkDefault keeps that a one-liner.
      virtualisation.quadlet.enable = lib.mkDefault false;
      # systemd-hostnamed is activated two ways at once: varlink through
      # systemd-hostnamed.socket, and D-Bus through org.freedesktop.hostname1.
      # On a systemd bump switch-to-configuration stops both, and NetworkManager
      # — which it restarts in the same run — asks hostname1 before the socket
      # comes back, so systemd refuses to start the socket over an already-live
      # service and activation exits 4 (deploy-rs then rolls the host back).
      # Not restarting it is safe: hostnamed exits when idle, so the new binary
      # gets picked up on the next activation anyway.
      # https://github.com/NixOS/nixpkgs/issues/449092
      # Drop this once that issue is closed.
      systemd.services.systemd-hostnamed.restartIfChanged = false;

      nix.daemonCPUSchedPolicy = "idle";
      nix.daemonIOSchedClass = "idle";
      nix.settings = {
        experimental-features = ["nix-command" "flakes"];
        # Honor the substituters/trusted-public-keys declared in flake.nix's
        # nixConfig. Without this, nix prints "ignoring untrusted flake
        # configuration setting 'extra-substituters'" and drops the flake's
        # caches (e.g. niri.cachix.org, only declared there), silently falling
        # back to building from source on any host where the system-level
        # substituters list below doesn't already cover them.
        accept-flake-config = true;
        trusted-users = ["cramt" "root"];
        substituters = [
          "https://cramt.cachix.org"
          "https://yazi.cachix.org"
          "https://nvf.cachix.org"
          "https://nixos-raspberrypi.cachix.org"
        ];
        trusted-public-keys = [
          "cramt.cachix.org-1:F7DlWw50o0gCn5TxMuep2PPku+7L9dxTIarTnPaNvls="
          "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
          "nvf.cachix.org-1:GMQWiUhZ6ux9D5CvFFMwnc2nFrUHTeGaXRlVBXo+naI="
          "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
        ];
      };
      programs.nix-ld.enable = true;
      nixpkgs = {
        overlays = import ../../overlays inputs;
        config.allowUnfree = true;
      };
    };
  };
}

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
      # Workaround for upstream nixpkgs regression:
      # https://github.com/NixOS/nixpkgs/issues/535850
      # The current linux_zen build installs its image as `vmlinuz` (the
      # kernel's install.sh default name) instead of `bzImage`, while NixOS
      # still derives `system.boot.loader.kernelFile` from `kernel.target`
      # (= "bzImage"). The file is a valid bzImage, just renamed, so point the
      # bootloader at the real filename. Guarded to zen kernels so non-zen
      # hosts (eros/rpi) are unaffected. Remove once the issue is fixed.
      system.boot.loader.kernelFile =
        lib.mkIf (config.boot.kernelPackages.kernel.isZen or false)
          (lib.mkForce "vmlinuz");

      systemd.user.settings.Manager.DefaultEnvironment = ''"PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"'';
      stylix.enable = true;
      services.gnome.gcr-ssh-agent.enable = false;
      nix.package = pkgs.lix;
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

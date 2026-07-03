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
        # TEMPORARY: vesktop pins pnpm_10_29_2 (insecure) as its *build-time*
        # dep. Upstream nixpkgs already switched vesktop to pnpm_10 in commit
        # 4b3d28a (2026-06-29), but the nixos-unstable channel hasn't advanced
        # past it yet. This is build-time only (pnpm isn't in vesktop's runtime
        # closure) and keeps the Hydra cache hit.
        # NOTE TO FUTURE SELF: if you're here after bumping nixpkgs, check
        # `nix eval` — once the channel has the fix, DELETE this line.
        config.permittedInsecurePackages = ["pnpm-10.29.2"];
      };
    };
  };
}

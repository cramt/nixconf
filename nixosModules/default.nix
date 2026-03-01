{
  pkgs,
  inputs,
  ...
}: {
  imports = [
    inputs.home-manager.nixosModules.home-manager
    inputs.stylix.nixosModules.stylix
    inputs.foundryvtt.nixosModules.foundryvtt
    inputs.nixarr.nixosModules.default
    inputs.quadlet-nix.nixosModules.quadlet
    ./portselector.nix
  ];

  config = {
    # https://github.com/pop-os/cosmic-session/issues/166#issuecomment-3613536888
    systemd.user.extraConfig = ''
      DefaultEnvironment="PATH=/run/wrappers/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
    '';
    stylix.enable = true;
    services.gnome.gcr-ssh-agent.enable = false;
    nix.package = pkgs.lix;
    nix.daemonCPUSchedPolicy = "idle";
    nix.daemonIOSchedClass = "idle";
    nix.settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["cramt" "root"];
      substituters = [
        "https://yazi.cachix.org"
        "https://nvf.cachix.org"
      ];
      trusted-public-keys = [
        "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
        "nvf.cachix.org-1:GMQWiUhZ6ux9D5CvFFMwnc2nFrUHTeGaXRlVBXo+naI="
      ];
    };
    programs.nix-ld.enable = true;
    nixpkgs = {
      overlays = import ../overlays inputs;
      config = {
        allowUnfree = true;
      };
    };
  };
}

{
  description = "Nixos config flake";

  nixConfig = {
    extra-substituters = [
      "https://cramt.cachix.org"
      "https://yazi.cachix.org"
      "https://nvf.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
      "https://niri.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cramt.cachix.org-1:F7DlWw50o0gCn5TxMuep2PPku+7L9dxTIarTnPaNvls="
      "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
      "nvf.cachix.org-1:GMQWiUhZ6ux9D5CvFFMwnc2nFrUHTeGaXRlVBXo+naI="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-ruby-downgrade.url = "github:nixos/nixpkgs/nixos-26.05";

    # TEMPORARY: nixos-unstable's vesktop (1.6.5) still builds against electron_40,
    # which is now EOL and refused by nixpkgs as insecure (electron <41 is marked
    # insecure). This is the branch of nixpkgs PR #542528 (approved + mergeable),
    # which moves vesktop to the supported electron_42 by relaxing its exact
    # electron-major assertion to a `>=` check. overlays/default.nix pulls
    # pkgs.vesktop from here. REMOVE this input + that overlay once #542528 reaches
    # nixos-unstable (a `just update` will carry the fix) and go back to plain
    # pkgs.vesktop. Track: https://github.com/NixOS/nixpkgs/pull/542528
    nixpkgs-vesktop-electron42.url = "github:mothzarella/nixpkgs/vesktop-electron42";
    nixarr.url = "github:nix-media-server/nixarr";
    jellarr.url = "github:cramt/jellarr";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";

    claude-code.url = "github:sadjow/claude-code-nix";

    # Herdr — agent-aware terminal multiplexer ("tmux for coding agents").
    # Not in nixpkgs; the upstream flake exposes packages.default + an overlay.
    # Remote use ("herdr --remote luna") rides plain SSH like tmux — no daemon.
    herdr = {
      url = "github:ogulcancelik/herdr";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Community-maintained Nix flake for the pi coding agent (https://pi.dev).
    # There is no official flake; lukasl-dev/pi.nix exposes the package,
    # an overlay, and NixOS/Home Manager modules (programs.pi.coding-agent).
    pi = {
      url = "github:lukasl-dev/pi.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Paseo — self-hosted orchestrator for coding agents (Claude Code, Codex,
    # OpenCode, ...) with desktop/mobile/web/CLI clients. The upstream flake
    # exposes packages (paseo daemon+CLI, and a Linux `desktop` Electron app)
    # plus a NixOS module. Deliberately NOT following our nixpkgs: the package is
    # a buildNpmPackage whose npmDepsHash is pinned against upstream's own
    # nixpkgs; overriding it would break the FOD hash (upstream's package.nix
    # documents an `.override { npmDepsHash = ... }` escape hatch for that case).
    paseo.url = "github:getpaseo/paseo";

    # OpenAI-compatible proxy for M365 Copilot (Nitro service + NixOS module).
    m365-copilot-proxy = {
      url = "github:cramt/m365-copilot-proxy";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nous Research Hermes Agent — self-hosted autonomous agent. The flake
    # exposes nixosModules.default + packages. Deliberately NOT following our
    # nixpkgs: it's a large Python app pinned against its own nixpkgs, and
    # overriding that risks breaking the build.
    hermes-agent.url = "github:NousResearch/hermes-agent";

    winapps = {
      url = "github:winapps-org/winapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    nh.url = "github:nix-community/nh";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprshell = {
      url = "github:H3rmt/hyprshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    cosmic-manager = {
      url = "github:HeitorAugustoLN/cosmic-manager";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };

    yazi.url = "github:sxyazi/yazi";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-index-database = {
      url = "github:Mic92/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-colors.url = "github:misterio77/nix-colors";

    nur.url = "github:nix-community/NUR";

    nix-ld = {
      url = "github:Mic92/nix-ld";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nvf = {
      url = "github:notashelf/nvf";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    foundryvtt.url = "github:nix-foundryvtt/nix-foundryvtt";

    homelab_system_controller = {
      url = "github:cramt/homelab_system_controller";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    git_update_notifier = {
      url = "github:cramt/git_update_notifier";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    probe-rs-rules = {
      url = "github:jneem/probe-rs-rules";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    helium-browser.url = "github:schembriaiden/helium-browser-nix-flake";

    zen-browser.url = "github:0xc000022070/zen-browser-flake";

    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    opnix = {
      url = "github:brizzbuzz/opnix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    import-tree.url = "github:vic/import-tree";

    niri-flake.url = "github:sodiboo/niri-flake";

    noctalia-shell = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/nixos-unstable";
    nixpkgs-rpi.follows = "nixos-raspberrypi/nixpkgs";

    # Permanent fork: upstream rewrote the hash-generation pipeline around a
    # `.targets.json` that pre-22.03 OpenWrt releases don't ship, so it can no
    # longer produce hashes for 19.07.x — the last release with the bcm53xx
    # Archer C5 v2 profile. This fork keeps the older builder + cached hashes
    # for 19.07.10 and carries the bcm53xx variantless-imagebuilder fix.
    openwrt-imagebuilder = {
      url = "github:cramt/nix-openwrt-imagebuilder";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dewclaw = {
      url = "github:MakiseKurisu/dewclaw";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;}
    (inputs.import-tree ./modules);
}

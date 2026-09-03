{
  description = "Nixos config flake";

  nixConfig = {
    extra-substituters = [
      "https://cramt.cachix.org"
      "https://yazi.cachix.org"
      "https://nvf.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
      "https://niri.cachix.org"
      "https://cache.numtide.com"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cramt.cachix.org-1:F7DlWw50o0gCn5TxMuep2PPku+7L9dxTIarTnPaNvls="
      "yazi.cachix.org-1:Dcdz63NZKfvUCbDGngQDAZq6kOroIrFoyO064uvLh8k="
      "nvf.cachix.org-1:GMQWiUhZ6ux9D5CvFFMwnc2nFrUHTeGaXRlVBXo+naI="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
      "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-26.05";

    nixarr.url = "github:nix-media-server/nixarr";
    jellarr.url = "github:cramt/jellarr";
    nix-flatpak.url = "github:gmodena/nix-flatpak";
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";

    claude-code.url = "github:sadjow/claude-code-nix";

    # mattpocock/skills — engineering-process skills for Claude Code (spec →
    # tickets → triage → implement → review, on `gh issue`). Upstream ships it
    # through Claude Code's plugin marketplace; we take the repo directly and
    # symlink the skill dirs ourselves, so `just update` moves them like
    # everything else. Not a flake, just a skills tree.
    mattpocock-skills = {
      url = "github:mattpocock/skills";
      flake = false;
    };

    # numtide's package set for coding-agent tooling; we use it for
    # `cli-proxy-api` (router-for-me/CLIProxyAPI), which ships no flake of its
    # own. Their CI bumps the pin daily and prebuilds into cache.numtide.com
    # (added to extra-substituters above), so this costs no local Go build.
    # Deliberately NOT following our nixpkgs: the package pins go_1_26 to match
    # upstream's go.mod and carries an unpinGoModVersionHook, both of which are
    # resolved against their nixpkgs.
    llm-agents.url = "github:numtide/llm-agents.nix";

    # Web control panel for cli-proxy-api, shipped as one self-contained
    # management.html per release. The proxy would otherwise fetch it from
    # GitHub on first request and re-check every 3h; as an input it is locked
    # and `just update` moves it. The URL must stay on /latest/download so
    # relocking actually picks up new releases.
    cli-proxy-api-panel = {
      url = "file+https://github.com/router-for-me/Cli-Proxy-API-Management-Center/releases/latest/download/management.html";
      flake = false;
    };

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

    # oh-my-pi (binary: `omp`) — can1357's fork of pi, with an official flake
    # exposing packages.omp and homeManagerModules.default (programs.omp).
    # Deliberately NOT following our nixpkgs: it builds a Rust core + a Bun
    # bundle against a pinned toolchain, and upstream CI only prebuilds that
    # exact closure into nix-community.cachix.org (added to the substituters
    # below) — re-pointing nixpkgs would miss every cache hit and build ~80k
    # lines of Rust locally.
    omp.url = "github:can1357/oh-my-pi";

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

    # T3 Code — self-hosted coding-agent orchestrator. No upstream flake and no
    # published binary, so we build the monorepo ourselves (packages/t3code).
    #
    # Tracks upstream main. This used to be pinned to StiensWout/t3code, the
    # head of PR #7211 (a real Pi provider driver), which is stacked on the
    # maintainer branch behind PR #2829 ("introduce new orchestrator") and so
    # dragged in apps/server/src/orchestration-v2 with it.
    #
    # That fork is incompatible with the hosted client at app.t3.codes, which
    # is built from main. Both sides expose `orchestration.dispatchCommand`,
    # but the payload union differs: main creates a project by dispatching a
    # `project.create` command through it, while orchestration-v2 moved project
    # mutations out to a separate `projects.mutate` RPC and dropped every
    # `project.*` member from the dispatch union. So the cloud client's "add
    # project" failed schema decode at the RPC boundary — no handler, no span,
    # no log line, and a bare "An error occurred." in the UI. Same story for
    # provider.auth.*, provider.install.* and pullRequests.*, which main calls
    # and orchestration-v2 has no handler for.
    #
    # Cost of coming back: no Pi driver. Upstream ships five drivers
    # (claude/codex/cursor/grok/opencode) and no Pi one, and shows no sign of
    # growing one — 21 community PRs adding Pi have been opened since 2026-04
    # and every one was closed unmerged. If Pi matters more than the cloud
    # client later, the fork is a one-line revert plus `providers.pi` in
    # hosts/luna/configuration.nix and "pi" in knownDrivers
    # (modules/services/t3code.nix) — but note the two orchestrators share
    # migration ids 044-047 with different contents, so the state.sqlite is not
    # portable in either direction.
    #
    #   https://github.com/pingdotgg/t3code/pull/7211  (Pi provider)
    #   https://github.com/pingdotgg/t3code/pull/2829  (the orchestrator-v2 base)
    t3code-src = {
      url = "github:pingdotgg/t3code";
      flake = false;
    };

    # Pure-Nix builder for pnpm v9 lockfiles; used by packages/t3code to
    # materialize node_modules without running `pnpm install` in the sandbox.
    pnpm2nix = {
      url = "github:cramt/pnpm2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    winapps = {
      url = "github:winapps-org/winapps";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Games that need more than "install it from nixpkgs" — each package carries
    # its own workarounds. Currently Legends of Runeterra, which is blocked by
    # Riot's Packman anti-tamper on current wine and so pins GE-Proton8-27-LoL.
    # See https://github.com/cramt/lor-on-linux for the investigation.
    nix-games = {
      url = "github:cramt/nix-games";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    # Upstream Rust toolchains with per-target rust-std. nixpkgs' rustc ships no
    # wasm32-wasip2 std and no wasm-component-ld, which is what Zed builds dev
    # extensions against; without them Zed falls back to `rustup target add` and
    # dies because there's no rustup. https://github.com/zed-industries/zed/issues/42353
    # Drop back to pkgs.{cargo,rustc,rustfmt} if nixpkgs ever ships wasip2.
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
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

    # PINNED to the last NUR revision whose repos.json.lock predates
    # AtaraxiaSjel/nur@f57371a8 ("fix: nixfmt and deadnix", 2026-08-25). deadnix
    # stripped the unused `pkgs` argument from that repo's
    # pkgs/python3Packages/default.nix, but its pkgs/default.nix still passes
    # `pkgs = final;` when building pythonPackagesExtensions, so anything that
    # forces python3Packages dies with
    #   error: function 'anonymous lambda' called with unexpected argument 'pkgs'
    # nur.repos.ataraxiasjel.waydroid-script (modules/virtualization/waydroid.nix,
    # saturn only) forces exactly that. Both NUR revs pulled in by this update pin
    # the broken AtaraxiaSjel commit 6a71c98f, so bumping NUR alone does not help.
    # Unpin once NUR's repos.json.lock moves past an AtaraxiaSjel revision that
    # takes the argument back (or adds an ellipsis).
    nur.url = "github:nix-community/NUR/11ec9dd83f6ca438de98749608af73f6877c62c5";

    nix-ld = {
      url = "github:Mic92/nix-ld";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    stylix = {
      # TEMPORARY fork: stylix indexes its paletteGenerator by hostPlatform
      # rather than buildPlatform, so a cross build feeds the builder an
      # aarch64 executable and IFD dies with "Exec format error" — which is what
      # broke mercury-img-cross on CI's x86 runners. The option is internal +
      # readOnly, so it can't be overridden from here. The branch is our pinned
      # upstream rev plus that four-line fix, nothing else.
      # Back to github:nix-community/stylix once the fix is merged upstream.
      url = "github:cramt/stylix/palette-generator-build-platform";
      inputs = {
        nixpkgs.follows = "nixpkgs";

        # Stylix fetches gnome-shell's sass sources to build the themed
        # gresource that GDM's greeter uses (saturn and mars run gdm), so this
        # tarball is pulled during *eval* of every host. gitlab.gnome.org
        # rate-limits GitHub Actions runners and answers with an HTML error
        # page instead of the tarball, which nix reports as "Failed to open
        # archive (Unrecognized archive format)" — the same locked rev fetched
        # fine the day before. GNOME mirrors the repo to GitHub, so point at
        # the same tag there; the narHash is unchanged, i.e. identical trees.
        # Keep this tag in sync with stylix's own flake.nix declaration —
        # if it bumps past ours, stylix's shell patches stop applying (loudly).
        # Remove once stylix stops sourcing gnome-shell from gitlab.gnome.org.
        gnome-shell = {
          url = "github:GNOME/gnome-shell/50.1";
          flake = false;
        };
      };
    };

    nvf = {
      url = "github:notashelf/nvf";
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

    # Terasic's linux-socfpga fork — mercury's kernel. Mainline has had Agilex 5
    # SoC support since 6.6, but socfpga_agilex5_de25_nano.dtb exists only here,
    # so we can't just use nixpkgs' kernel. Not a flake, it's a kernel tree.
    # A branch rather than a tag because that's all Terasic publishes; the lock
    # pins the rev, so `just update` is what moves the board's kernel — if mercury
    # ever boot-loops after an update PR, this input is the first suspect.
    terasic-linux-socfpga = {
      url = "github:terasic/linux-socfpga/de25_nano_revA_v1.0";
      flake = false;
    };

    # Fleet deployment: builds each host's toplevel locally and activates it over
    # SSH with magic rollback. Driven by `just deploy` (see modules/flake/deploy.nix).
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # progress-engine — exact draw-probability tests for decklists, and the
    # canonical parser for Archidekt decklist format. The mtg-commander skill's
    # `scryfall` helper shells out to it rather than carrying a second copy of
    # that parser: `check` and `play` must agree on what a decklist *is*, or a
    # deck validates at 100 cards and then deals a different 100.
    progress-engine = {
      url = "github:cramt/progress-engine";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;}
    (inputs.import-tree ./modules);
}

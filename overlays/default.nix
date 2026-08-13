inputs: [
  inputs.nur.overlays.default

  # Exposes niri-stable/niri-unstable and xwayland-satellite-stable/-unstable
  # under pkgs.*. We use niri-stable (v25.08) + xwayland-satellite-stable, which
  # have niri's integrated xwayland-satellite support (no manual DISPLAY juggling).
  inputs.niri-flake.overlays.niri

  # noctalia 5.x (native Wayland+GLES rewrite, no longer quickshell). Exposes
  # `pkgs.noctalia` (v5) — distinct from nixpkgs' older quickshell-based
  # `pkgs.noctalia-shell` (4.7.x), which is left untouched. We consume pkgs.noctalia
  # to match the v5 homeModule we import (modules/hm-base/default-hm.nix). The v5
  # shell avoids the quickshell layer-shell-over-IPC crash that cosmic-comp
  # triggers on multi-output setups.
  inputs.noctalia-shell.overlays.default

  (final: prev: let
    sources = import ../npins;
    npinspkgs = import sources.nixpkgs {
      inherit (prev.stdenv.hostPlatform) system;
    };
    rest = builtins.removeAttrs sources ["nixpkgs" "__functor"];
  in {
    npinsSources = builtins.mapAttrs (_: x: x {pkgs = npinspkgs;}) rest;
  })

  # Pre-unlock the gpg agent by signing a throwaway payload before the TUI takes
  # over, so signing a commit from inside lazygit never needs a pinentry prompt
  # mid-TUI. Shadows pkgs.lazygit so every consumer gets the wrapper.
  (final: prev: {
    lazygit = prev.writeScriptBin "lazygit" ''
      echo 'a' | ${prev.gnupg}/bin/gpg --sign -u alex.cramt@gmail.com > /dev/null && ${prev.lazygit}/bin/lazygit
    '';
  })

  # Permanent preference, not a workaround: the patch zeroes SSD_HEIGHT (36 -> 0)
  # so cosmic-comp draws no server-side title bar on windows it decorates itself.
  # Nothing upstream to track — COSMIC has no setting for this.
  # doCheck disables rustPlatform's default (nixpkgs sets nothing) — the reason
  # predates this comment and isn't recorded; drop the line on the next COSMIC
  # bump and see whether the check phase actually passes.
  (final: prev: {
    cosmic-comp = prev.cosmic-comp.overrideAttrs (old: {
      patches = (old.patches or []) ++ [../patches/no_ssd.patch];
      doCheck = false;
    });
  })

  # Shared definitions for the GPU-accelerated llama.cpp builds used by the
  # llama-cpp / llama-cpp-rpc services. These are cache misses by construction
  # (Hydra doesn't build ROCm/CUDA variants), so they're exposed as flake
  # packages (modules/flake/packages.nix) and prebuilt in CI. Keeping the
  # override here means the service modules and the prebuilt flake packages
  # resolve to the exact same store path.
  (final: prev: let
    # nixpkgs' llama-cpp rpcSupport post-install still runs
    # `cp bin/rpc-server $out/bin/llama-rpc-server`, but upstream llama.cpp
    # renamed that binary to `ggml-rpc-server` (cmake installs it under that
    # name). Bridge the old name in the build tree so the copy succeeds and the
    # service still finds `$out/bin/llama-rpc-server`. Guarded so it becomes a
    # no-op once nixpkgs catches up to the rename.
    withRpcServerFix = pkg:
      pkg.overrideAttrs (old: {
        postBuild =
          (old.postBuild or "")
          + ''
            if [ ! -e bin/rpc-server ] && [ -e bin/ggml-rpc-server ]; then
              ln -s ggml-rpc-server bin/rpc-server
            fi
          '';
      });
  in {
    llama-cpp-rocm-rpc = withRpcServerFix (prev.llama-cpp.override {
      rocmSupport = true;
      rpcSupport = true;
    });
    llama-cpp-cuda-rpc = withRpcServerFix (prev.llama-cpp.override {
      cudaSupport = true;
      rpcSupport = true;
    });
  })

  (final: prev: {
    cockatrice = prev.callPackage ../packages/cockatrice {};
  })

  # Not in nixpkgs; built from source (Go + embedded Svelte frontend).
  # Bump version + hashes in ../packages/agentsview/default.nix.
  (final: prev: {
    agentsview = prev.callPackage ../packages/agentsview {};
  })

  # nixpkgs now ships its own agent-browser (0.27.0) which lags the version we
  # track. Point pkgs.agent-browser at our local build so every consumer
  # (development bundle, claude-code feature) resolves to the same store path
  # and home-manager's buildEnv doesn't see two conflicting versions.
  # Bump version + hash in ../packages/agent-browser/default.nix.
  (final: prev: {
    agent-browser = prev.callPackage ../packages/agent-browser {};
  })

  # Not in nixpkgs and no upstream flake — the whole pnpm 11 monorepo is built
  # from source with pnpm2nix. Chunky (the web app alone is a ~2min rolldown
  # build on top of the full dependency farm), so let CI prebuild it into
  # cachix rather than building on a host. Source is pinned by inputs.t3code-src
  # and moves with `nix flake update`.
  (final: prev: {
    t3code = prev.callPackage ../packages/t3code {
      pnpm2nix = inputs.pnpm2nix.lib.${prev.stdenv.hostPlatform.system};
      src = inputs.t3code-src;
    };
  })

  # paseo desktop app + daemon come from inputs.paseo, which isn't in nixpkgs.
  # The 0.2.1 npmDepsHash override that used to live here is gone: upstream's
  # checked-in nix/npm-deps.hash is CI-verified again as of 0.2.2, so the
  # packages build unmodified.
  (final: prev: let
    system = prev.stdenv.hostPlatform.system;
  in {
    paseo = inputs.paseo.packages.${system}.default;
    paseo-desktop = inputs.paseo.packages.${system}.desktop;
  })

  # niri-stable (v25.08) links libdisplay-info-sys 0.2.2, which only binds a
  # system libdisplay-info of the same major.minor. nixpkgs dropped
  # `libdisplay-info_0_2` (keeping only _0_3 and the current 0.4) and left a
  # *throwing* alias in its place, so niri-flake's `libdisplay-info_0_2 ?
  # libdisplay-info` fallback never fires — callPackage still finds the
  # attribute — and its `assert libdisplay-info_0_2.version == "0.2.0"` blows up
  # during eval of every host with niri enabled. Rebuilding 0.2.0 (rather than
  # pointing at _0_3) is deliberate: 0.3 would be an ABI mismatch for the crate.
  # Upstream: https://github.com/sodiboo/niri-flake/issues/1851, fix in flight as
  # https://github.com/sodiboo/niri-flake/pull/1853, which resurrects 0.2.0 the
  # same way. Remove once that PR lands and our niri-flake pin includes it.
  (final: prev: {
    libdisplay-info_0_2 = prev.libdisplay-info.overrideAttrs {
      version = "0.2.0";
      src = prev.fetchFromGitLab {
        domain = "gitlab.freedesktop.org";
        owner = "emersion";
        repo = "libdisplay-info";
        rev = "0.2.0";
        hash = "sha256-6xmWBrPHghjok43eIDGeshpUEQTuwWLXNHg7CnBUt3Q=";
      };
    };
  })

  (final: prev: {
    julia = prev.julia.withPackages ["JuliaFormatter" "LanguageServer"];
  })

  (final: prev: {
    docker = prev.docker.override {
      buildxSupport = true;
    };
  })

  # Fix faugus-launcher subprocess calls: faugus-run invokes `sys.executable -m faugus.components`
  # which spawns bare python3 without site-packages, so deps like `requests` are missing.
  # Workaround for nixpkgs#423927 (buildPythonPackage incomplete wrapping).
  (final: prev: let
    py3 = prev.python3;
    faugusDeps = with py3.pkgs; [
      pillow
      psutil
      pygobject3
      requests
      vdf
    ];
  in {
    faugus-launcher = prev.faugus-launcher.overrideAttrs (old: {
      preFixup = (old.preFixup or "") + ''
        makeWrapperArgs+=(--prefix PYTHONPATH : "$out/${py3.sitePackages}:${py3.pkgs.makePythonPath faugusDeps}")
      '';
    });
  })
]

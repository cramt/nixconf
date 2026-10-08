inputs: [
  inputs.nur.overlays.default

  # Exposes niri-stable/niri-unstable and xwayland-satellite-stable/-unstable
  # under pkgs.*. We use niri-stable (v25.08) + xwayland-satellite-stable, which
  # have niri's integrated xwayland-satellite support (no manual DISPLAY juggling).
  inputs.niri-flake.overlays.niri

  # noctalia 5.x (native Wayland+GLES rewrite, no longer quickshell). Exposes
  # `pkgs.noctalia` (v5) — distinct from nixpkgs' older quickshell-based
  # `pkgs.noctalia-shell` (4.7.x), which is left untouched. We consume pkgs.noctalia
  # and feed it to home-manager's own programs.noctalia module. The v5
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

  (import ./local-packages.nix).overlay

  # colibrì's GPU tiers: ROCm/Vulkan builds Hydra never caches. Spelled out
  # HERE rather than .override'd inside the service module so that
  # modules/services/colibri.nix, which selects one of these by name, and the
  # prebuilt flake package resolve to the same store path.
  #
  # gfx1101 = Navi 32 = saturn's RX 7800 XT, and it is a compile-time target,
  # not llama.cpp's runtime HSA_OVERRIDE_GFX_VERSION — RDNA3 has WMMA matrix
  # cores, which is what rocWMMA needs to map the CUDA nvcuda::wmma kernels onto.
  (final: prev: {
    colibri-rocm = final.colibri.override {
      rocmSupport = true;
      rocmGpuTarget = "gfx1101";
    };
    # RADV compute path. Upstream measures the VRAM-resident int4 expert
    # primitive ~35% faster than ROCm/HIP on RDNA4 — unmeasured on RDNA3, which
    # is exactly why both variants are built and A/B'd rather than one being
    # declared the winner up front (docs/saturn-llm-storage.md).
    colibri-vulkan = final.colibri.override {
      vulkanSupport = true;
    };
  })

  # Zed's Delta agent, as `zed-delta` (`delta` is git-delta).
  inputs.delta-nix.overlays.default

  (final: prev: {
    # Zed extensions that aren't in its registry, so `programs.zed-editor.extensions`
    # can't reach them. Prebuilt here into Zed's installed-extension layout and
    # symlinked in by modules/hm-features/zed.nix. See packages/mkZedExtension.nix.
    mkZedExtension = prev.callPackage ../packages/mkZedExtension.nix {
      rustToolchain = let
        fenix = inputs.fenix.packages.${prev.stdenv.hostPlatform.system};
      in
        fenix.combine [
          fenix.stable.rustc
          fenix.stable.cargo
          fenix.targets.wasm32-wasip2.stable.rust-std
        ];
    };

    zed-spade = final.mkZedExtension {src = final.npinsSources.zed-spade;};
    zed-vixen = final.mkZedExtension {src = final.npinsSources.vixen-zed;};
  })

  # T3 Code comes from llm-agents (release-tracked, bumped daily by numtide).
  # Their build ships with T3 Connect compiled out, which is what we want: luna
  # is reached through caddy + authelia (modules/services/t3code.nix), not
  # Ping's cloud relay. Only the wrapper is overridden, so the unwrapped build
  # still comes straight from cache.numtide.com.
  #
  # Switching from our old pnpm2nix build: that one launched electron on a bare
  # main.cjs, so safeStorage sometimes keyed off the keyring entry for app
  # "Electron" instead of "T3 Code (Alpha)". Anything it encrypted that way
  # (seen: connection-catalog.json) fails with ElectronSafeStorageDecryptError
  # now. Fix: decrypt under app name "Electron" and re-encrypt under
  # "T3 Code (Alpha)" (done on mars 2026-10-02).
  #
  # providerPackages is emptied because the agents t3code spawns should be the
  # home-manager ones (claude-code's config, auth, etc.), not a second copy
  # pinned by llm-agents.
  (final: prev: let
    t3code = inputs.llm-agents.packages.${prev.stdenv.hostPlatform.system}.t3code.override {
      providerPackages = [];
    };
  in {
    inherit t3code;
    t3code-desktop = final.symlinkJoin {
      name = "t3code-desktop-${t3code.version}";
      paths = [t3code.desktop];
      meta = t3code.meta // {mainProgram = "t3code-desktop";};
    };
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

  # ffmpeg 9.0 dropped AVVulkanDeviceContext's queue_family_decode_index /
  # nb_decode_queues fields, which moonlight 6.1.0's plvk.cpp still reads, so it
  # fails to compile against the default ffmpeg. Upstream took the same fix in
  # https://github.com/NixOS/nixpkgs/pull/552212 (merged 2026-08-13), wiring
  # ffmpeg_8 straight into the package and dropping the `ffmpeg` argument.
  # Our main nixpkgs now carries that commit, but eros builds from nixpkgs-rpi,
  # which does not — so the override is still needed there and throws
  # everywhere else. Hence the argument probe; drop the whole block once
  # nixpkgs-rpi catches up and the probe is false on every host.
  # final, not prev: eros applies nixos-raspberrypi's overlays after this one,
  # which swap in the Pi-accelerated `ffmpeg-rpi` (already 8.x, so it was never
  # broken). Reading through `final` keeps eros on ffmpeg-rpi and leaves its
  # moonlight derivation bit-identical; `prev` would silently downgrade the TV
  # kiosk to a generic ffmpeg and force an aarch64 rebuild.
  (final: prev: {
    # Conditional on the value, not on the attrset: gating the attribute itself
    # forces moonlight-qt while the overlay's names are still being computed,
    # which is infinite recursion.
    moonlight-qt =
      if prev.moonlight-qt.override.__functionArgs or {} ? ffmpeg
      then prev.moonlight-qt.override {ffmpeg = final.ffmpeg_8;}
      else prev.moonlight-qt;
  })

  (final: prev: {
    docker = prev.docker.override {
      buildxSupport = true;
    };
  })
]

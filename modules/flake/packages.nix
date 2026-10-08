{ inputs, ... }:
{
  perSystem = { pkgs, lib, system, ... }: let
    saturnPkgs = inputs.self.nixosConfigurations.saturn.pkgs;
    erosPkgs = inputs.self.nixosConfigurations.eros.pkgs;

    # Every packages/<name> (overlays/local-packages.nix), taken from a host's
    # overlaid package set rather than built here: the store paths are then
    # byte-identical to what that host builds, so CI's prebuild is exactly what
    # it substitutes. Also what `nix-update --flake <name>` reads meta.position
    # off. Each package is exported once: x86 if it builds there, else aarch64.
    localPackages = hostPkgs: keep:
      lib.filterAttrs (_: keep)
      (lib.genAttrs (import ../../overlays/local-packages.nix).names (n: hostPkgs.${n}));
  in {
    packages = lib.optionalAttrs (system == "x86_64-linux") ({
      # `nix run .#flash-eros -- /dev/sdX` — flash a ready-to-boot eros SD card.
      # Builds the aarch64 SD image (substituted from cache), then bakes the
      # local /etc/opnix-token into the image's rootfs /etc *post-build* (via a
      # loopback mount — we need sudo for the flash anyway), so opnix works on
      # first boot with no manual step and the token never enters the nix store.
      # Flashes with a pv progress bar + ETA. Runs on the flashing host (x86);
      # references the aarch64 image as a build input.
      flash-eros = let
        sdImage = inputs.self.nixosConfigurations.eros.config.system.build.sdImage;
      in pkgs.writeShellApplication {
        name = "flash-eros";
        runtimeInputs = with pkgs; [ zstd pv util-linux coreutils ];
        text = ''
          dev="''${1:-}"
          if [ ! -b "$dev" ]; then
            echo "usage: nix run .#flash-eros -- /dev/sdX   (target block device)" >&2
            exit 1
          fi
          token="''${OPNIX_TOKEN:-/etc/opnix-token}"
          if [ ! -r "$token" ]; then
            echo "cannot read opnix token at $token (set OPNIX_TOKEN=/path)" >&2
            exit 1
          fi

          work="$(mktemp --suffix=.img)"
          mnt="$(mktemp -d)"
          loop=""
          cleanup() {
            mountpoint -q "$mnt" && sudo umount "$mnt" || true
            [ -n "$loop" ] && sudo losetup -d "$loop" 2>/dev/null || true
            rm -rf "$work" "$mnt"
          }
          trap cleanup EXIT

          echo ">> decompressing SD image..."
          imgs=(${sdImage}/sd-image/*.img.zst)
          zstd -d -f -o "$work" "''${imgs[0]}"

          echo ">> baking /etc/opnix-token into rootfs (needs sudo)..."
          loop="$(sudo losetup -Pf --show "$work")"
          # rpi sd-image layout: p1 = FAT firmware, p2 = ext4 root (NIXOS_SD).
          # Wait for the partition node to appear (losetup -P + udev is async).
          root="''${loop}p2"
          for _ in 1 2 3 4 5 6 7 8 9 10; do [ -b "$root" ] && break; sleep 1; done
          if [ ! -b "$root" ]; then echo "rootfs partition $root never appeared" >&2; exit 1; fi
          sudo mount "$root" "$mnt"
          sudo install -D -m0640 -o0 -g0 "$token" "$mnt/etc/opnix-token"
          sudo umount "$mnt"
          sudo losetup -d "$loop"; loop=""

          echo ">> target device:"
          lsblk -do NAME,SIZE,MODEL,TRAN "$dev" || true
          read -r -p ">> ERASE $dev and flash eros? type 'yes' to confirm: " ans
          if [ "$ans" != "yes" ]; then echo "aborted"; exit 1; fi

          echo ">> flashing (pv shows progress + ETA)..."
          pv "$work" | sudo dd of="$dev" bs=4M conv=fsync oflag=direct
          sync
          echo ">> done — eject and boot eros."
        '';
      };

      # Same mercury host, cross-compiled from x86 instead of built natively — for
      # iterating on saturn without waiting on the ARM runner or emulating a
      # thing. extendModules keeps it one config plus one line, so the two can't
      # drift; the store paths differ, so this deliberately does NOT share cachix
      # hits with `mercury-img`. Use it for local turnaround, trust the native one
      # for what actually gets flashed.
      #
      # NOT currently buildable on a stock x86 machine, and skipped in
      # build-matrix.sh for that reason — saturn only gets away with it because
      # binfmt executes the aarch64 bits. One blocker is fixed: the stylix fork
      # pinned in flake.nix, whose paletteGenerator was indexed by hostPlatform
      # and so ran an aarch64 binary at IFD time.
      #
      # The next one is home-manager instantiating its own nixpkgs at the host
      # system, making every HM derivation a native aarch64 build that an x86
      # runner rejects with "Reason: platform mismatch". Do NOT fix that by
      # forcing HM's pkgs arg to the cross set: it works, but only exposes
      # btop-nvml putting makeWrapper in buildInputs instead of
      # nativeBuildInputs, and nixpkgs raises that at *eval* time — which fails
      # `nix flake check` and takes `just deploy` down for every host, not just
      # this package. Left evaluable-but-unbuildable on purpose until btop-nvml
      # is fixed upstream.
      mercury-img-cross = let
        crossed = inputs.self.nixosConfigurations.mercury.extendModules {
          modules = [{ nixpkgs.buildPlatform = "x86_64-linux"; }];
        };
      in pkgs.runCommand "mercury-img-cross" {} ''
        cp ${crossed.config.system.build.sdImage}/sd-image/*.img $out
      '';

      # NOTE: scripts/windows-vm.sh (boot the physical Windows partition in a VM)
      # is SHELVED — Windows aborts very early on the synthesized disk topology
      # with no BSOD/log to diagnose. Kept in-tree as a reference but deliberately
      # NOT exposed as a flake app until someone kernel-debugs the early-boot abort.

      # Overlay patches and from-source GPU builds Hydra never caches, pulled
      # from saturn's package set for the same reason as localPackages.
      inherit
        (saturnPkgs)
        cosmic-comp
        # colibrì's GPU tiers. The HIP build compiles backend_cuda.cu through
        # hipcc for gfx1101 and the Vulkan one runs glslc over the compute
        # shaders — neither is anything Hydra has, and saturn is a desktop we'd
        # rather not have compiling HIP kernels.
        colibri-rocm
        colibri-vulkan
        ;
    }
    // localPackages saturnPkgs (p: lib.meta.availableOn saturnPkgs.stdenv.hostPlatform p)
    # Same reason, one layer down: UnityPy and the codec packages it needs are
    # hand-pinned PyPI version + hash, so each needs a flake attr for nix-update
    # to read meta.position off. Nothing installs them directly — they exist so
    # rhystic-tracker's wrapper can put a python holding them on the app's PATH.
    # Imported rather than callPackage'd, because callPackage staples
    # override/overrideDerivation onto the set it returns and those would then
    # show up as flake packages of their own.
    // import ../../packages/rhystic-tracker/python {
      inherit (saturnPkgs) python3Packages;
    })
    // lib.optionalAttrs (system == "aarch64-linux") (
    # What x86 can't build (steamlink, a prebuilt arm64 binary), from eros,
    # the host that runs it.
    localPackages erosPkgs (p: !lib.meta.availableOn saturnPkgs.stdenv.hostPlatform p
      && lib.meta.availableOn erosPkgs.stdenv.hostPlatform p)
    // {
      # nixos-raspberrypi exposes the SD image at config.system.build.sdImage
      # (instead of the upstream installer's `images.sd-card` path). aarch64
      # only — eros is a Raspberry Pi, so building this on x86 would emulate.
      eros-img = pkgs.runCommand "eros-img" {} ''
        ${pkgs.zstd}/bin/unzstd -d \
          ${inputs.self.nixosConfigurations.eros.config.system.build.sdImage}/sd-image/* \
          -o $out
      '';

      # mercury (Terasic DE25-Nano) SD image, built natively on aarch64 — this is
      # the one CI builds on the ARM runner and pushes to cachix, per the repo's
      # build policy. sdImage.compressImage is off for this host (the flash is a
      # plain dd), so there is nothing to decompress.
      mercury-img = pkgs.runCommand "mercury-img" {} ''
        cp ${inputs.self.nixosConfigurations.mercury.config.system.build.sdImage}/sd-image/*.img $out
      '';
    });
  };
}

{ inputs, ... }:
{
  perSystem = { pkgs, lib, system, ... }: {
    packages = lib.optionalAttrs (system == "x86_64-linux") {
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
      mercury-img-cross = let
        crossed = inputs.self.nixosConfigurations.mercury.extendModules {
          modules = [{ nixpkgs.buildPlatform = "x86_64-linux"; }];
        };
      in pkgs.runCommand "mercury-img-cross" {} ''
        cp ${crossed.config.system.build.sdImage}/sd-image/*.img $out
      '';

      # `nix run .#saturn-windows-image -- --build-only` (then `-- --deploy-only
      # /dev/…-part1`). Builds a debloated Windows 11 image in a headless raw-qemu
      # VM (NVMe disk so it boots on saturn unchanged, no sysprep) and flashes it
      # onto a partition. Ships Discord/1Password/Zen via winget at first logon;
      # the AMD driver deliberately does NOT come from here (the build VM has no
      # GPU) and arrives via Windows Update on first bare-metal boot.
      #
      # Uses any ISO it finds (~/Downloads included) before falling back to
      # uupdump. Verified on 25H2 (26200): ConX is bypassed by forcing
      # setup.exe /legacy, and the answer file's locale + edition are derived
      # from install.wim rather than assumed — hardcoding en-US against
      # "English International" (en-GB-only) media is what previously made
      # Setup silently fall back to the interactive installer.
      #
      # Body lives in scripts/saturn-windows-image.sh; capture/deploy self-sudo.
      # See its --help.
      saturn-windows-image = pkgs.callPackage ../../packages/saturn-windows-image {};

      # NOTE: scripts/windows-vm.sh (boot the physical Windows partition in a VM)
      # is SHELVED — Windows aborts very early on the synthesized disk topology
      # with no BSOD/log to diagnose. Kept in-tree as a reference but deliberately
      # NOT exposed as a flake app until someone kernel-debugs the early-boot abort.

      # Custom / from-source derivations that Hydra never caches (overlay
      # patches, ROCm/CUDA builds). Pulled straight from saturn's overlaid
      # package set so the store paths are byte-identical to what the x86
      # hosts build. CI prebuilds these and pushes them to cachix so the
      # toplevel builds substitute instead of compiling for hours.
      inherit
        (inputs.self.nixosConfigurations.saturn.pkgs)
        cosmic-comp
        llama-cpp-rocm-rpc
        llama-cpp-cuda-rpc
        # colibrì's GPU tiers. The HIP build compiles backend_cuda.cu through
        # hipcc for gfx1101 and the Vulkan one runs glslc over the compute
        # shaders — neither is anything Hydra has, and saturn is a desktop we'd
        # rather not have compiling HIP kernels. The plain CPU `colibri` is
        # seconds to build and deliberately left out.
        colibri-rocm
        colibri-vulkan
        # Built from source through pnpm2nix (whole pnpm monorepo + a ~2min
        # rolldown build), so it wants prebuilding too. Version tracks
        # inputs.t3code-src, so `nix flake update` bumps it, not nix-update.
        t3code
        ;

      # Exposed so `nix-update --flake <name>` can locate them (it reads the
      # package's meta.position off the flake output). Bumped by `just
      # update_packages`. These are our locally-built overrides of packages
      # nixpkgs either lacks or lags on.
      inherit
        (inputs.self.nixosConfigurations.saturn.pkgs)
        agentsview
        agent-browser
        cockatrice
        ;
    } // lib.optionalAttrs (system == "aarch64-linux") {
      # Steam Link client — aarch64 only because it's a prebuilt arm64 binary.
      steamlink = pkgs.callPackage ../../packages/steamlink {};

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
    };
  };
}

{ inputs, ... }:
{
  perSystem = { pkgs, lib, system, ... }: {
    packages = lib.optionalAttrs (system == "x86_64-linux") {
      # OpenWrt sysupgrade image for the Archer C5 v2 (host: titan). The upstream
      # ImageBuilder ships only x86_64-linux binaries, so gate accordingly.
      titan-img = import ../../hosts/titan/configuration.nix { inherit pkgs inputs; };

      # Dewclaw deployment environment for titan. `nix build .#titan-deploy`
      # produces a buildEnv whose `bin/` contains a deploy-titan script that
      # SSHes into the router and applies the UCI config declared in
      # hosts/titan/dewclaw.nix.
      titan-deploy = pkgs.callPackage inputs.dewclaw {
        configuration = import ../../hosts/titan/dewclaw.nix;
      };

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
    };
  };
}

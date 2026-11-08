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

    # `nix run .#flash-<host> [-- /dev/sdX]`: dd a host's raw SD image onto a
    # card. With no argument it picks the only removable disk; it refuses
    # non-removable ones outright, since the image is the size of a whole disk
    # and a typo'd /dev/sdX would otherwise eat a data drive.
    #
    # `bake` customises a scratch copy of the image before it's written, for
    # secrets that must never enter the nix store. It's { runtimeInputs; text; }:
    # text runs with the writable copy at $work and must define bake_cleanup.
    mkFlash = { host, img, bake ? null }: pkgs.writeShellApplication {
      name = "flash-${host}";
      runtimeInputs = with pkgs; [ pv util-linux coreutils gawk ]
        ++ lib.optionals (bake != null) bake.runtimeInputs;
      text = ''
        img=${img}
        dev="''${1:-}"

        if [ -z "$dev" ]; then
          mapfile -t removable < <(lsblk -dnpo NAME,RM,TYPE | awk '$2 == 1 && $3 == "disk" { print $1 }')
          if [ "''${#removable[@]}" -ne 1 ]; then
            echo "found ''${#removable[@]} removable disks, pass one: nix run .#flash-${host} -- /dev/sdX" >&2
            lsblk -dpo NAME,SIZE,RM,TRAN,MODEL >&2
            exit 1
          fi
          dev="''${removable[0]}"
        fi

        if [ ! -b "$dev" ] || [ "$(lsblk -dno TYPE "$dev")" != disk ]; then
          echo "$dev is not a whole block device" >&2
          exit 1
        fi
        if [ "$(lsblk -dno RM "$dev" | tr -d ' ')" != 1 ]; then
          echo "$dev is not removable, refusing" >&2
          exit 1
        fi
      '' + lib.optionalString (bake != null) ''

        token="''${OPNIX_TOKEN:-/etc/opnix-token}"
        if [ ! -r "$token" ]; then
          echo "cannot read opnix token at $token (set OPNIX_TOKEN=/path)" >&2
          exit 1
        fi

        work="$(mktemp --suffix=.img)"
        cleanup() { bake_cleanup; rm -f "$work"; }
        trap cleanup EXIT
        cp --sparse=always "$img" "$work"
        chmod u+w "$work"
        ${bake.text}
        img="$work"
      '' + ''

        echo ">> target device:"
        lsblk -po NAME,SIZE,MODEL,TRAN,MOUNTPOINTS "$dev"
        read -r -p ">> ERASE $dev and flash ${host}? type 'yes' to confirm: " ans
        if [ "$ans" != "yes" ]; then echo "aborted"; exit 1; fi

        # A card from a previous flash gets its partitions automounted.
        lsblk -lnpo NAME,MOUNTPOINT "$dev" | awk 'NF == 2 { print $1 }' | while read -r part; do
          sudo umount "$part"
        done

        echo ">> flashing $(du -hL "$img" | cut -f1)..."
        pv "$img" | sudo dd of="$dev" bs=4M conv=fsync oflag=direct status=none
        sync
        echo ">> done, eject and boot ${host}."
      '';
    };

    # opnix hosts get the local /etc/opnix-token baked into the image's rootfs
    # (p2, the sd-image.nix layout every board here uses) through a loopback
    # mount, so opnix works on first boot with no manual step.
    bakeOpnixToken = {
      runtimeInputs = [ ];
      text = ''
        mnt="$(mktemp -d)"
        loop=""
        bake_cleanup() {
          if mountpoint -q "$mnt"; then sudo umount "$mnt"; fi
          if [ -n "$loop" ]; then sudo losetup -d "$loop" 2>/dev/null || true; fi
          rm -rf "$mnt"
        }

        echo ">> baking $token into a copy of the image (needs sudo)..."
        loop="$(sudo losetup -Pf --show "$work")"
        # losetup -P hands partition scanning to udev, so the node shows up late.
        root="''${loop}p2"
        for _ in 1 2 3 4 5 6 7 8 9 10; do [ -b "$root" ] && break; sleep 1; done
        if [ ! -b "$root" ]; then echo "rootfs partition $root never appeared" >&2; exit 1; fi
        sudo mount "$root" "$mnt"
        sudo install -D -m0640 -o0 -g0 "$token" "$mnt/etc/opnix-token"
        sudo umount "$mnt"
        sudo losetup -d "$loop"; loop=""
      '';
    };

    # The installer ISO is read-only iso9660, so its wifi PSKs go on a small FAT
    # partition appended after it (the hybrid MBR has two free slots), as ready
    # NetworkManager keyfiles. `nmcli --offline` writes them so escaping is
    # NM's problem, and mtools fills the partition in place: no sudo, no mount.
    installerWifiLabel = "NIXWIFI";
    bakeInstallerWifi = {
      runtimeInputs = with pkgs; [ dosfstools mtools networkmanager saturnPkgs._1password-cli ];
      text = ''
        conns="$(mktemp -d)"
        bake_cleanup() { rm -rf "$conns"; }
        OP_SERVICE_ACCOUNT_TOKEN="$(cat "$token")"
        export OP_SERVICE_ACCOUNT_TOKEN

        echo ">> baking wifi PSKs from 1Password onto the stick..."
      '' + lib.concatStrings (lib.mapAttrsToList (name: net: ''
        nmcli --offline connection add type wifi con-name ${lib.escapeShellArg name} \
          ssid ${lib.escapeShellArg net.ssid} wifi-sec.key-mgmt wpa-psk \
          wifi-sec.psk "$(op read ${lib.escapeShellArg net.pskRef})" \
          > "$conns/${name}.nmconnection"
      '') (import ../../myLib/wifi.nix)) + ''

        start=$(( ($(stat -c %s "$work") / 512 + 2047) / 2048 * 2048 ))
        truncate -s $(( (start + 16384) * 512 )) "$work"
        echo "start=$start, size=16384, type=c" \
          | sfdisk --quiet --no-reread --no-tell-kernel --append "$work" 2>/dev/null
        mkfs.fat -F 12 -n ${installerWifiLabel} --offset "$start" "$work" 8192 >/dev/null
        mcopy -i "$work@@$(( start * 512 ))" "$conns"/*.nmconnection ::
      '';
    };

    # Generic rescue/install USB for the x86 hosts (the SD-card boards have
    # their own images above). Deliberately host-agnostic: it's just sshd with
    # the fleet keys, so `just install <host>` can push that host's closure
    # from a working machine. Nothing host-specific, and no copy of this flake,
    # lives on the stick, so it never goes stale between flashes.
    installer = inputs.nixpkgs.lib.nixosSystem {
      modules = [
        "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
        ({ pkgs, ... }: {
          nixpkgs.hostPlatform = "x86_64-linux";
          # The router's DNS picks this up from DHCP: `ssh root@installer`.
          networking.hostName = "installer";
          users.users.root.openssh.authorizedKeys.keys = (import ../../myLib/keys.nix).alex;
          console.keyMap = "dk-latin1";
          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          environment.systemPackages = [ pkgs.disko pkgs.git ];

          # Wifi baked onto the stick by flash-installer (bakeInstallerWifi).
          # Not WantedBy the partition's device unit: the stick is the boot
          # device, already plugged in the initrd, so stage 2 never sees it
          # appear and the wants never fire. A stick dd'ed some other way has
          # no such partition, which is a no-op rather than a failed unit.
          systemd.services.installer-wifi = {
            description = "Load the wifi connections baked onto the installer stick";
            wantedBy = [ "multi-user.target" ];
            after = [ "systemd-udev-trigger.service" "NetworkManager.service" ];
            serviceConfig.Type = "oneshot";
            path = [ pkgs.mtools pkgs.networkmanager ];
            environment.MTOOLS_SKIP_CHECK = "1";
            script = ''
              part=/dev/disk/by-label/${installerWifiLabel}
              for _ in $(seq 20); do [ -e "$part" ] && break; sleep 0.5; done
              if [ ! -e "$part" ]; then echo "no $part, stick wasn't flashed with wifi"; exit 0; fi
              dir=/etc/NetworkManager/system-connections
              install -d -m700 "$dir"
              mcopy -n -i "$part" '::*.nmconnection' "$dir/"
              chmod 600 "$dir"/*.nmconnection
              nmcli connection reload
            '';
          };

          # xz (the default) roughly triples build time for ~10% smaller ISO.
          isoImage.squashfsCompression = "zstd -Xcompression-level 6";
        })
      ];
    };
  in {
    packages = lib.optionalAttrs (system == "x86_64-linux") ({
      installer-iso = pkgs.runCommand "installer-iso" {} ''
        ln -s ${installer.config.system.build.isoImage}/iso/*.iso $out
      '';

      # The ISO is hybrid, so a plain dd onto a USB stick boots (UEFI + BIOS).
      flash-installer = mkFlash {
        host = "installer";
        img = inputs.self.packages.${system}.installer-iso;
        bake = bakeInstallerWifi;
      };

      # The images are built for the board's own arch (cachix has them from the
      # ARM runner); only the wrapper is x86.
      flash-eros = mkFlash {
        host = "eros";
        img = inputs.self.packages.aarch64-linux.eros-img;
        bake = bakeOpnixToken;
      };
      flash-mercury = mkFlash {
        host = "mercury";
        img = inputs.self.packages.aarch64-linux.mercury-img;
        bake = bakeOpnixToken;
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
      # The remaining one is home-manager instantiating its own nixpkgs at the
      # host system, making every HM derivation a native aarch64 build that an
      # x86 runner rejects with "Reason: platform mismatch". venus fixes exactly
      # that by forcing HM's pkgs arg to the cross set (see its
      # configuration.nix); this extendModules would need the same override.
      mercury-img-cross = let
        crossed = inputs.self.nixosConfigurations.mercury.extendModules {
          modules = [{ nixpkgs.buildPlatform = "x86_64-linux"; }];
        };
      in pkgs.runCommand "mercury-img-cross" {} ''
        cp ${crossed.config.system.build.sdImage}/sd-image/*.img $out
      '';

      # venus (Zybo) SD image. venus is cross-built by its own config, so this
      # x86 leg is the one that gets flashed, unlike mercury's.
      venus-img = pkgs.runCommand "venus-img" {} ''
        cp ${inputs.self.nixosConfigurations.venus.config.system.build.sdImage}/sd-image/*.img $out
      '';

      # venus has no opnix, so there's nothing to bake in.
      flash-venus = mkFlash {
        host = "venus";
        img = inputs.self.packages.${system}.venus-img;
      };

      # Overlay patches and from-source GPU builds Hydra never caches, pulled
      # from saturn's package set for the same reason as localPackages.
      inherit
        (saturnPkgs)
        cosmic-comp
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

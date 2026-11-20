# rosinante: the rescue USB for the x86 hosts. Unlike the bare `installer`
# stick it's a fleet member in everything but deploys: built through
# myLib.mkSystem with every nixosModule, so it joins the tailnet
# (rosinante.<tailnet>), renders op-secrets, and cramt gets the same `claude`
# (through the pool) and shell as everywhere else, with a nixconf checkout in
# ~/nixconf to eval and nixos-install from.
#
# It lives outside hosts/ on purpose: every directory there is a deploy target
# and a CI leg, and a live ISO is neither. Built by `nix run .#flash-rosinante`,
# which bakes the wifi PSKs and /etc/opnix-token onto a FAT partition after
# the ISO (modules/flake/packages.nix), so nothing secret enters the store.
{
  inputs,
  lib,
  pkgs,
  ...
}: let
  stickLabel = "ROSINANTE";
in {
  imports = [
    "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  myNixOS = {
    bundles.general.enable = true;
    bundles.general.stylixAsset = ../../media/artemis2_1.jpg;
    bundles.users.enable = true;
    services.sshd.enable = true;
    # Nothing scrapes a stick that's plugged in for an hour.
    services.metrics.exporter.enable = false;
  };

  # The installer's root ssh, with the fleet keys, so `just install <host>
  # rosinante` works against this stick as it does against `installer`.
  users.users.root.openssh.authorizedKeys.keys = (import ../../myLib/keys.nix).alex;
  # Straight onto a shell as cramt at the console, not the ISO's `nixos` user.
  services.getty.autologinUser = lib.mkForce "cramt";

  console.keyMap = "dk-latin1";
  services.xserver.xkb = {
    layout = "dk";
    variant = "nodeadkeys";
  };

  environment.systemPackages = with pkgs; [
    disko
    git
    efibootmgr
    gptfdisk
    parted
    pciutils
    usbutils
    ghostty.terminfo
  ];

  # Wifi and the 1Password token, baked onto the stick by flash-rosinante.
  # Not WantedBy the partition's device unit: the stick is the boot device,
  # already there in the initrd, so stage 2 never sees it appear.
  systemd.services.rosinante-stick = {
    description = "Load wifi and the opnix token baked onto the rescue stick";
    wantedBy = ["multi-user.target"];
    before = ["op-secrets.service"];
    requiredBy = ["op-secrets.service"];
    after = ["systemd-udev-trigger.service" "NetworkManager.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [pkgs.mtools pkgs.networkmanager pkgs.coreutils];
    environment.MTOOLS_SKIP_CHECK = "1";
    script = ''
      part=/dev/disk/by-label/${stickLabel}
      for _ in $(seq 20); do [ -e "$part" ] && break; sleep 0.5; done
      if [ ! -e "$part" ]; then echo "no $part, stick wasn't flashed by flash-rosinante"; exit 0; fi
      dir=/etc/NetworkManager/system-connections
      install -d -m700 "$dir"
      mcopy -n -i "$part" '::*.nmconnection' "$dir/"
      chmod 600 "$dir"/*.nmconnection
      nmcli connection reload
      mcopy -n -i "$part" ::opnix-token /etc/opnix-token
      chmod 640 /etc/opnix-token
    '';
  };

  # A real clone when github answers, so it can pull and (with a forwarded
  # agent) push; otherwise the exact tree this stick was built from.
  systemd.services.rosinante-nixconf = {
    description = "Check out nixconf into ~cramt/nixconf";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target" "home-manager-cramt.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "cramt";
    };
    path = [pkgs.git pkgs.coreutils];
    script = ''
      dest="$HOME/nixconf"
      [ -e "$dest" ] && exit 0
      if timeout 60 git clone https://github.com/cramt/nixconf.git "$dest"; then
        git -C "$dest" remote set-url --push origin git@github.com:cramt/nixconf.git
      else
        echo "github unreachable, using the snapshot baked into the stick"
        cp -r --no-preserve=mode ${inputs.self} "$dest"
        git -C "$dest" init -q -b main
        git -C "$dest" remote add origin git@github.com:cramt/nixconf.git
        git -C "$dest" add -A
        git -C "$dest" -c user.name=rosinante -c user.email=rosinante@localhost commit -qm "snapshot from the rosinante stick"
      fi
    '';
    environment.HOME = "/home/cramt";
  };

  # xz (the default) roughly triples build time for ~10% smaller ISO.
  isoImage.squashfsCompression = "zstd -Xcompression-level 6";

  system.stateVersion = "26.05";
}

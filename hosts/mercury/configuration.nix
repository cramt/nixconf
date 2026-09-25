# mercury — Terasic DE25-Nano, an Agilex 5 SoC FPGA dev board (HPS side only).
#
# Everything the board itself needs — Terasic's kernel, the U-Boot -> extlinux
# boot chain, the SD image layout — lives in A-H-Technology/nixos-fpga, which is
# where to look for why any of it is the way it is. This file is only what makes
# the board a fleet member: users, home-manager, and opting out of fleet
# defaults that don't fit a headless 957 MB ARM board.
{
  inputs,
  pkgs,
  lib,
  ...
}: {
  imports = [
    inputs.nixos-fpga.nixosModules.terasic-de25-nano
    inputs.nixos-fpga.nixosModules.terasic-de25-nano-sd-image
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  image.baseName = "mercury";

  # nixosModules.default ships lix/zfs, neither of which has cached aarch64
  # builds worth having on a 957 MB board. Same reasoning as eros — but note
  # stylix deliberately stays ON here, see below. (quadlet used to need
  # disabling too; it now defaults off in modules/base/nixos-default.nix.)
  #
  # zfs still needs mkForce because it's enabled at normal priority by an input's
  # module (nixarr), not by anything in this repo — drop the mkForce if that ever
  # becomes conditional upstream.
  nix.package = pkgs.nix;
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # Alex ssh's in from Ghostty, which exports TERM=xterm-ghostty; without the
  # matching terminfo entry every login greets her with "can't find terminal
  # definition". Same fix luna and ganymede already carry.
  environment.systemPackages = [
    pkgs.ghostty.terminfo
  ];

  myNixOS = {
    services.sshd.enable = true;

    # Unlike eros, mercury keeps the general bundle and stylix on. It isn't a
    # desktop bundle — it's the fleet's system baseline (locale, timezone, nh,
    # comma, trippy, udev) — and it's also what supplies stylix.image/cursor/
    # fonts. stylix can't just be switched off here either: hm-base/default-hm.nix
    # reads config.stylix.enable directly, so with stylix's HM module absent the
    # whole evaluation dies on `attribute 'stylix' missing`. eros escapes that
    # only by importing none of the repo's HM modules at all.
    bundles.general = {
      enable = true;
      stylixAsset = ../../media/artemis2_1.jpg;
    };
  };

  # mercury opts out of myNixOS.bundles.users for the same reason eros does: that
  # bundle puts every user in libvirtd/docker/gamemode/storage/pipewire, none of
  # which exist here, so useradd fails during activation. Wire the account and
  # its keys directly instead.
  #
  # sshd here is key-only (the module sets PasswordAuthentication = false and
  # PermitRootLogin = prohibit-password) and nothing sets a password, so without
  # these keys the board boots onto the network completely unreachable — the
  # serial console can't rescue it either, since an account with no password set
  # is locked rather than empty.
  programs.zsh.enable = true;

  users.users = {
    cramt = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = (import ../../myLib/keys.nix).alex;
    };

    # `just deploy` activates as root over SSH, so deploy-rs needs this
    # independently of the cramt account. mercury is already in deploy.nodes.
    root.openssh.authorizedKeys.keys = (import ../../myLib/keys.nix).alex;
  };

  security.sudo.wheelNeedsPassword = false;

  # ./home.nix is written against myHomeManager.*, and those options only exist
  # if the repo's HM module set is imported — bundles.users does that per user,
  # and we opted out above, so replicate its import list here. Without this the
  # file is inert: home-manager.users evaluates empty and nothing is applied.
  home-manager = {
    # Deliberately no useGlobalPkgs/useUserPackages, unlike eros: the repo's
    # hmModules.default sets HM-side `nixpkgs` options, and useGlobalPkgs asserts
    # against those. bundles.users sets neither for the same reason.
    backupFileExtension = "hm-bak";
    extraSpecialArgs = {inherit inputs;};

    users.cramt = _: let
      hm = inputs.self.outputs.homeManagerModules;

      # Exactly the features hm-bundles/general.nix switches on, and nothing
      # else. bundles.users imports *every* feature and bundle, which is fine on
      # a desktop but here dragged niri (a whole Wayland compositor, ~300 Rust
      # crates), 1Password, GTK/Qt/Kvantum theming and Blender presets into the
      # closure — 490 derivations compiled from source on the ARM runner for a
      # board with no display at all. Keep this list in sync with that bundle.
      cliFeatures = [
        "btop"
        "fzf"
        "git"
        "gpg-agent"
        "lazygit"
        "neovim"
        "nix-index"
        "nushell"
        "ssh"
        "starship"
        "yazi"
        "zellij"
        "zoxide"
        "zsh"
      ];
    in {
      imports =
        [
          (import ./home.nix)
          hm.default
          hm.bundles.general
          inputs.nix-index-database.homeModules.nix-index
        ]
        ++ map (n: hm.features.${n}) cliFeatures;
    };

    # sharedModules is deliberately left alone (eros clears it, we can't): it is
    # how stylix's HM module arrives, and hm-base/default-hm.nix reads
    # config.stylix.enable directly, so clearing it makes `attribute 'stylix'
    # missing` at eval.
    #
    # It is also how niri-flake's HM module arrives, which used to make this
    # board build a whole Wayland compositor for a config.kdl it would never
    # read; that is now neutralized centrally in modules/desktop/niri.nix for
    # every host that doesn't set myNixOS.niri.enable. Likewise the git feature's
    # 1Password signer, which now follows myHomeManager.ssh.use1Password —
    # home.nix already sets that false.
  };

  # 4 cores and ~957 MB: this board substitutes, it never compiles. `just deploy`
  # already builds locally and only copies closures out, so this holds anyway.
  nix.settings.max-jobs = 1;

  system.stateVersion = "26.05";
}

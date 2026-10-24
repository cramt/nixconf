# venus — Digilent Zybo (the original, Zynq-7010), mercury's Xilinx counterpart
# (PS side only).
#
# Everything the board itself needs — U-Boot SPL, the extlinux boot chain, the
# SD image layout — lives in A-H-Technology/nixos-fpga. This file is only what
# makes the board a fleet member, and it deliberately tracks
# hosts/mercury/configuration.nix; the comments there explain the shared bits.
# What's here is what differs: venus is 32-bit and cross-built.
{
  inputs,
  config,
  pkgs,
  lib,
  ...
}: let
  # Shared by the system and home-manager package sets, which are imported
  # separately (see home-manager below).
  boardOverlay = _: prev: {
    # libpcap (via iptables) pulls rdma-core for InfiniBand, which the Zybo
    # doesn't have, and rdma-core's CMake rejects the build-platform Python
    # when cross-compiling.
    libpcap = prev.libpcap.override {withRdma = false;};

    # Drops yazi's image/video previewers (imagemagick, ffmpeg, chafa, resvg,
    # poppler): there's no screen to preview on, and imagemagick alone drags
    # fftw and a cross gfortran in.
    yazi = prev.yazi.override {
      optionalDeps = with prev; [jq _7zz fd ripgrep fzf zoxide];
    };
  };
in {
  imports = [
    inputs.nixos-fpga.nixosModules.digilent-zybo
    inputs.nixos-fpga.nixosModules.digilent-zybo-sd-image
  ];

  # Hydra builds nothing for armv7l and the Cortex-A9s have 512 MB between
  # them, so cross from x86: whoever runs `just deploy` builds it.
  nixpkgs = {
    hostPlatform = "armv7l-linux";
    buildPlatform = "x86_64-linux";
  };

  nixpkgs.overlays = [boardOverlay];

  image.baseName = "venus";

  nix.package = pkgs.nix;
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # Ghostty sets TERM=xterm-ghostty, but even the build-platform ghostty misses
  # the cache here (the board overlay shifts its hash), so taking its terminfo
  # output means building the terminal, gtk4 and all. ncurses ships the same
  # entry as plain `ghostty`; recompile it under Ghostty's name instead.
  environment.systemPackages = [
    (pkgs.buildPackages.runCommand "xterm-ghostty-terminfo" {
        nativeBuildInputs = [pkgs.buildPackages.ncurses];
      } ''
        mkdir -p $out/share/terminfo
        infocmp -x -A ${pkgs.buildPackages.ncurses}/share/terminfo ghostty \
          | sed 's/^ghostty|/xterm-ghostty|ghostty|/' > ghostty.src
        tic -x -o $out/share/terminfo ghostty.src
      '')
  ];

  # nh wraps nix-output-monitor, which is Haskell, and GHC doesn't cross-compile
  # to armv7l. Nothing runs `nh os switch` here anyway: deploys come from
  # elsewhere, and nix.gc covers what nh's clean did.
  # clean has its own timer that doesn't follow enable.
  programs.nh = {
    enable = lib.mkForce false;
    clean.enable = lib.mkForce false;
  };

  # Nobody generates a config on this board, and the tool hard-depends
  # on bcachefs-tools, whose fusemount.rs doesn't compile on 32-bit (tv_sec is
  # i32, so unsigned_abs() hands Duration::from_secs a u32).
  system.tools.nixos-generate-config.enable = false;

  # nix-ld is for running foreign binaries, which nobody does on this board,
  # and it doesn't compile for 32-bit ARM (mismatched pointer-width types).
  programs.nix-ld.enable = lib.mkForce false;

  myNixOS = {
    services.sshd.enable = true;
    bundles.general = {
      enable = true;
      stylixAsset = ../../media/artemis2_1.jpg;
    };
  };

  # stylix stays on for the CLI themes (see mercury), but its Qt target
  # installs qt5ct/qt6ct, i.e. two whole Qt builds plus GTK3, for a board with
  # no display.
  stylix.targets.qt.enable = false;

  programs.zsh.enable = true;

  users.users = {
    cramt = {
      isNormalUser = true;
      extraGroups = ["wheel"];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = (import ../../myLib/keys.nix).alex;
    };
    root.openssh.authorizedKeys.keys = (import ../../myLib/keys.nix).alex;
  };

  security.sudo.wheelNeedsPassword = false;

  home-manager = {
    backupFileExtension = "hm-bak";
    extraSpecialArgs = {inherit inputs;};

    users.cramt = hmArgs: let
      hm = inputs.self.outputs.homeManagerModules;

      # Same list as mercury, so keep the two in sync.
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

      # home-manager imports its own nixpkgs with only `system` set, so it would
      # build this user's whole environment natively for armv7l, which nothing
      # in the fleet can do. Re-import it as the same cross set the system uses.
      # useGlobalPkgs would get there too, but it asserts against the HM-side
      # nixpkgs options hmModules.default sets (see mercury).
      _module.args.pkgs = lib.mkForce (import inputs.nixpkgs {
        localSystem = config.nixpkgs.buildPlatform;
        crossSystem = config.nixpkgs.hostPlatform;
        inherit (hmArgs.config.nixpkgs) config;
        overlays = hmArgs.config.nixpkgs.overlays ++ [boardOverlay];
      });
    };
  };

  # 2 cores and 512 MB: this board substitutes, it never compiles.
  nix.settings.max-jobs = 1;

  system.stateVersion = "26.05";
}

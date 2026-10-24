{
  config,
  pkgs,
  lib,
  ...
}: {
  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    bundles.general.enable = true;
    ssh.use1Password = false;
    ssh.desktopEntries = false;
    gpg-agent.enableSshSupport = false;

    # Headless: the Zybo's HDMI and VGA are wired to the PL, so there is no
    # display until a bitstream provides a video pipeline. Same as mercury.
    monitors = [];

  };

  # nix-index-database publishes no armv7l database, so neither its comma nor
  # its nix-index can evaluate here. Importing its module is enough to switch
  # nix-index on (mkDefault true), hence forcing that too. The system's plain
  # comma still works; it builds its index on first use. Drop both once
  # nix-community/nix-index-database ships an armv7l-linux database.
  myHomeManager.nix-index.enable = lib.mkForce false;
  programs.nix-index.enable = lib.mkForce false;

  # The neovim feature turns on neovide, a GUI with nothing to draw on here.
  # Its bindgen hook also needs a GCC that runs on armv7l, and that GCC's
  # libgomp fails to cross-build.
  programs.neovide.enable = lib.mkForce false;

  # Renders a KDE colour scheme through imagemagick, which drags in fftw and a
  # cross gfortran. There's no KDE to read it.
  stylix.targets.kde.enable = false;
  # HM's own Qt target, separate from the system one configuration.nix disables:
  # qt5ct/qt6ct again, LLVM included this time.
  stylix.targets.qt.enable = false;

  home.stateVersion = "26.05";
}

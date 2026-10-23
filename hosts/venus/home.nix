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

  home.stateVersion = "26.05";
}

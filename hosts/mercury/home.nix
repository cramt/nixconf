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

    # Headless: the DE25's HDMI is driven from the FPGA fabric, so there is no
    # display until a bitstream provides a video pipeline. configuration.nix
    # therefore imports only the CLI feature modules, so there is deliberately
    # no hyprland.enable/niri.enable to switch off here — those options simply
    # don't exist on this host.
    monitors = [];
  };

  home.stateVersion = "26.05";
}

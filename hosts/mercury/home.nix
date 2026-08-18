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
    hyprland.enable = false;

    # Headless: the DE25's HDMI is driven from the FPGA fabric, so there is no
    # display until a bitstream provides a video pipeline.
    monitors = [];
  };

  home.stateVersion = "26.05";
}

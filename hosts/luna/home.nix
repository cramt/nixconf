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
    bundles.development.enable = true;
    hyprland = {
      enable = false;
      exec = "firefox --kiosk https://example.com";
    };
    monitors = [
      {
        port = "HDMI-A-1";
        name = "TODO";
        res = {
          width = 1920;
          height = 1080;
        };
        pos = {
          x = 0;
          y = 0;
        };
        workspace = 1;
        transform = 0;
        refresh_rate = null;
      }
    ];
  };

  # Where chipsmith-vendor installs Quartus (II 13.0sp1, Prime, Prime Pro) on
  # this machine: /pool has the room the home directory doesn't.
  home.sessionVariables.CHIPSMITH_INSTALL_ROOT = "/pool/dev/altera_pro";

  # nix-xilinx's FHS wrappers read this to find the imperative Vivado install
  # (AMD's installer can't be packaged); tmpfiles creates /pool/Xilinx in configuration.nix.
  xdg.configFile."xilinx/nix.sh".text = ''
    INSTALL_DIR=/pool/Xilinx
    VERSION=2026.1
  '';

  # The FPGA boards' Linux (mercury: DE25-Nano, venus: Zybo) authorize only the
  # Personal key, which luna holds on disk (t3code's onDiskSshKey) instead of
  # in a 1Password agent; without this, ssh offers the default keys and root
  # is refused. chipsmith's `flash --ssh` goes through it too.
  # The build-pool peers (ganymede, saturn) authorize the same key; agents on
  # luna borrow them for VMs and builds that don't fit here.
  programs.ssh.settings.${
    lib.concatMapStringsSep " " (h: "${h} ${h}.${(import ../../myLib/site.nix).tailnet_domain}")
      ["mercury" "venus" "ganymede" "saturn"]
  } = {
    IdentityFile = "/home/cramt/.ssh/id_personal";
    IdentitiesOnly = true;
  };

  home.stateVersion = "26.05";
}

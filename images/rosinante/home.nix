{...}: {
  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  myHomeManager = {
    bundles.general.enable = true;
    claude-code = {
      enable = true;
      # Ghidra is a gigabyte nobody needs to fix a bootloader.
      rea.enable = false;
    };
  };

  home.stateVersion = "26.05";
}

{...}: {
  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  # ganymede is a TV: emrakul is the session, and its apps are the web apps
  # declared system-wide in web-apps.nix. Nothing graphical lives here.
  myHomeManager.bundles.general.enable = true;
  # Toolchain and the claude CLI for the t3code agents.
  myHomeManager.bundles.development.enable = true;

  home.stateVersion = "26.05";
}

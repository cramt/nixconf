{
  config,
  pkgs,
  lib,
  ...
}: {
  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  # The paseo daemon runs headless as cramt, so 1Password's ssh-agent and
  # op-ssh-sign (which need the desktop app) are unavailable. Use the personal
  # SSH key that opnix drops on-disk for both GitHub auth and commit signing so
  # agents can actually clone/commit/push. The path below is opnix's key
  # re-emitted with a trailing newline by the paseo module (modules/services/
  # paseo.nix) — OpenSSH rejects the raw opnix file without it.
  programs.ssh.matchBlocks."github.com" = {
    identityFile = "/home/cramt/.ssh/id_paseo";
    identitiesOnly = true;
    extraOptions.StrictHostKeyChecking = "accept-new";
  };
  programs.git.settings = {
    gpg.ssh.program = lib.mkForce "${pkgs.openssh}/bin/ssh-keygen";
    user.signingKey = lib.mkForce "/home/cramt/.ssh/id_paseo";
  };

  myHomeManager = {
    bundles.general.enable = true;
    bundles.development.enable = true;
    ssh.use1Password = false;
    gpg-agent.enableSshSupport = false;
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

  home.stateVersion = "26.05";
}

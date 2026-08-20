{
  config,
  pkgs,
  lib,
  ...
}: {
  home.username = "cramt";
  home.homeDirectory = "/home/cramt";

  # The T3 Code server runs headless as cramt, so 1Password's ssh-agent and
  # op-ssh-sign (which need the desktop app) are unavailable. Use the personal
  # SSH key that opnix drops on-disk for both GitHub auth and commit signing so
  # agents can actually clone/commit/push. The path below is opnix's key
  # re-emitted with a trailing newline by the t3code module (modules/services/
  # t3code.nix) — OpenSSH rejects the raw opnix file without it.
  programs.ssh.settings."github.com" = {
    IdentityFile = "/home/cramt/.ssh/id_paseo";
    IdentitiesOnly = true;
    StrictHostKeyChecking = "accept-new";
  };
  programs.git.settings = {
    gpg.ssh.program = lib.mkForce "${pkgs.openssh}/bin/ssh-keygen";
    user.signingKey = lib.mkForce "/home/cramt/.ssh/id_paseo";
  };

  myHomeManager = {
    bundles.general.enable = true;
    bundles.development.enable = true;
    # The development bundle pools Claude accounts behind cli-proxy-api, but
    # luna is deliberately kept off the pool. The `claude` wrapper notices the
    # proxy is not listening and falls back to the direct OAuth login.
    cli-proxy-api.enable = lib.mkForce false;
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

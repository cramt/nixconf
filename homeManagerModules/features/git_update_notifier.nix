{
  pkgs,
  inputs,
  ...
}: {
  systemd.user.services.git_update_notifier = let
    configFile = pkgs.writeText "config.json" (
      builtins.toJSON {
        repos = {
          "nixos-unstable" = {
            check_frequency_minutes = 1;
            repo = "https://github.com/NixOS/nixpkgs.git";
            branch = "nixos-unstable";
          };
        };
      }
    );
    envCommand = "CONFIG_FILE=${configFile}";
    binary = "${inputs.git_update_notifier.packages.${pkgs.stdenv.hostPlatform.system}.default}/bin/git_update_notifier";
  in {
    Service = {
      Environment = envCommand;
      ExecStart = binary;
    };
    Unit = {
      Description = "git update notifier";
    };
    Install = {
      WantedBy = ["network-online.target"];
    };
  };
}

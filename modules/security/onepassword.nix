# 1Password CLI and GUI
{ inputs, ... }: {
  flake.nixosModules."features.onepassword" = { config, lib, pkgs, ... }: {
    options.myNixOS.onepassword.enable = lib.mkEnableOption "myNixOS.onepassword";
    config = lib.mkIf config.myNixOS.onepassword.enable {
      environment.etc."1password/custom_allowed_browsers" = {
        text = ''
          zen
        '';
        mode = "0755";
      };
      programs._1password = {
        enable = true;
        package = (import inputs.nixpkgs-stable {inherit (pkgs.stdenv.hostPlatform) system; config.allowUnfree = true;})._1password-cli;
      };
      programs._1password-gui = {
        enable = true;
        polkitPolicyOwners = ["cramt"];
      };
    };
  };
}

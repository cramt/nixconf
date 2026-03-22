# Terraform remote state PostgreSQL backend
{ ... }: {
  flake.nixosModules."services.terraform_remote_backend" = { config, lib, ... }: {
    options.myNixOS.services.terraform_remote_backend.enable = lib.mkEnableOption "myNixOS.services.terraform_remote_backend";
    config = lib.mkIf config.myNixOS.services.terraform_remote_backend.enable {
      myNixOS.services.postgres = {
        enable = true;
        applicationUsers = [
          {
            name = "terraformremotestate";
            passwordFile = config.services.onepassword-secrets.secretPaths.terraformRemotePassword;
          }
        ];
      };
    };
  };
}

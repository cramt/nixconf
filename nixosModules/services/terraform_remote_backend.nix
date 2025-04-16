{...}: let
  terraform_remote_state_password = (import ../../secrets.nix).terraform_remote_state_password;
in {
  myNixOS.services.postgres = {
    enable = true;
    applicationUsers = [
      {
        name = "terraformremotestate";
        password = terraform_remote_state_password;
      }
    ];
  };
}

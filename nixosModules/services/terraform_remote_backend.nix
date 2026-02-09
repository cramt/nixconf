{config, ...}: {
  myNixOS.services.postgres = {
    enable = true;
    applicationUsers = [
      {
        name = "terraformremotestate";
        passwordFile = config.services.onepassword-secrets.secretPaths.terraformRemotePassword;
      }
    ];
  };
}

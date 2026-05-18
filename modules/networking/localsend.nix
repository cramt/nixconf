# LocalSend — cross-platform AirDrop alternative over local Wi-Fi
{ ... }: {
  flake.nixosModules."features.localsend" = { config, lib, ... }: {
    options.myNixOS.localsend.enable = lib.mkEnableOption "myNixOS.localsend";
    config = lib.mkIf config.myNixOS.localsend.enable {
      programs.localsend = {
        enable = true;
        openFirewall = true;
      };
    };
  };
}

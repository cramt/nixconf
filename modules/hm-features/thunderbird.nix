{ ... }: {
  hmModules.features.thunderbird = { config, lib, ... }: {
    options.myHomeManager.thunderbird.enable = lib.mkEnableOption "myHomeManager.thunderbird";
    config = lib.mkIf config.myHomeManager.thunderbird.enable {
      programs.thunderbird = {
        enable = true;
        profiles = { cramt = { isDefault = true; }; };
      };
    };
  };
}

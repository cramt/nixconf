{...}: {
  config = {
    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement = {
        enable = false;
        finegrained = true;
      };
      open = false;
      nvidiaSettings = true;
    };
  };
}

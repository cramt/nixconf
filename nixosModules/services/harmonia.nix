{ ... }: {
  services.harmonia = {
    enable = true;
    settings = {
      bind = "0.0.0.0:5000";
    };
  };
}

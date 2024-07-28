{ ... }: {
  programs.thunderbird = {
    enable = true;
    profiles = {
      cramt = {
        isDefault = true;
      };
    };
  };
}


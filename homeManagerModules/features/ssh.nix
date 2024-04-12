{ ... }: {
  programs.ssh = {
    enable = true;
    startAgent = true;
  };
}

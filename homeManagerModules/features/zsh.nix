{ ... }: {
  programs.zsh = {
    enable = true;
    initExtra = ''
      if [[ -z "''${SSH_AGENT_PID}" ]]
      then
        eval `ssh-agent -s` > /dev/null
      fi
    '';
  };
}

{ pkgs }: pkgs.writers.writeNuBin "kill_vesktop" ''
  ps --long | where command =~ "vesktop" | where ppid == 1 | each { 
    print $in
    $"kill ($in.pid)" | ${pkgs.zsh}/bin/zsh -c $in
  }
  null
''

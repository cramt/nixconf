{ pkgs }: pkgs.writers.writeNuBin "kill_vesktop" ''
  ps --long | where command =~ "vesktop" | where ppid == 1 | each { 
    kill $in.pid
  }
  null
''

{ pkgs }: pkgs.writeScriptBin "zellij_smart_start" ''
  #!${pkgs.nushell}/bin/nu
  let attched_sessions = ps --long | where command =~ "zellij --server" | each { 
    let value = $in.command | split row "/" | last | str replace "main" ""
    try { $value | into int }
  } | sort | enumerate | where $in.index == $in.item | get item
  let new_index = try { ($attched_sessions | last) + 1 } catch { 0 }
  ${pkgs.zellij}/bin/zellij attach $"main($new_index)" --create
''

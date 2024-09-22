{ pkgs, output, direction }: pkgs.writers.writeNuBin "sway_gaming" ''
  let on = try { open /tmp/gaming_mode | into bool} catch { false }
  let rect = ((swaymsg --raw -t get_outputs) | from json | filter { $in.name == "${output}" }).rect | first
  let change = (if $on {
    1
  } else {
    -1
  }) * ${toString direction}
  not $on | into string | save -f /tmp/gaming_mode
  swaymsg $"output ${output} pos ($change + $rect.x) ($change + $rect.y)"
  null
''

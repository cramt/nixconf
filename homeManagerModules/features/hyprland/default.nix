{pkgs, ...}: {
  config = {
    wayland.windowManager.hyprland = {
      enable = true;
      settings = {
        exec-once = ["rio"];
        "$mod" = "SUPER";
        input = {
          kb_layout = "dk";
          kb_variant = "nodeadkeys";
        };

        binds =
          [
            "$mod, T, exec, ${pkgs.rio}/bin/rio"
            "$mod, D, exec, ${pkgs.tofi}/bin/tofi-drun | xargs ${pkgs.hyprland}/bin/hyprctl dispatch exec --"
          ]
          ++ (
            builtins.concatLists (builtins.genList (
                i: let
                  ws = i + 1;
                in [
                  "$mod, code:1${toString i}, workspace, ${toString ws}"
                  "$mod SHIFT, code:1${toString i}, movetoworkspace, ${toString ws}"
                ]
              )
              9)
          );
      };
    };
  };
}

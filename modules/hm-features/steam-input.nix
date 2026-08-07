# Declarative Steam Input layouts.
#
# The couch tiles are web pages, so "controller support" means turning buttons
# into the keystrokes those pages already listen for. YouTube, Jellyfin and
# Nebula all settled on the same convention for that — f fullscreen, k/space
# play-pause, m mute, j/l seek, arrows navigate — so one layout covers all
# three and the same button does the same thing everywhere by construction
# rather than by three configs being kept in sync by hand.
#
# What this can and can't do declaratively: see scripts/steam_input.nix. Short
# version — the layout lands in Steam's template list from nix, and choosing it
# for a shortcut is a one-time click per tile in the controller settings.
{...}: {
  hmModules.features.steam-input = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.steam-input;

    writer = import ../../scripts/steam_input.nix {inherit pkgs;};

    spec = pkgs.writeText "steam-input.json" (
      builtins.toJSON (
        lib.mapAttrsToList (title: l: {
          inherit title;
          inherit (l) description bindings controllerType;
          slug = lib.toLower (builtins.replaceStrings [" "] ["-"] title);
        })
        cfg.layouts
      )
    );

    apply = pkgs.writeShellScriptBin "steam-input" ''
      exec ${writer}/bin/steam-input ${spec} ${lib.escapeShellArg cfg.templateDir}
    '';
  in {
    options.myHomeManager.steam-input = {
      enable = lib.mkEnableOption "myHomeManager.steam-input";

      templateDir = lib.mkOption {
        type = lib.types.str;
        default = "~/.local/share/Steam/controller_base/templates";
        description = ''
          Where Steam looks for layout templates. Inside the Steam install
          tree rather than under userdata, so Steam may replace it on update —
          which is why the layouts are re-applied on every activation.
        '';
      };

      layouts = lib.mkOption {
        default = {};
        description = ''
          Layouts to publish. The attribute name is the title shown in Steam's
          template list.

          Only layouts declared here are managed: this removes ones it wrote
          previously and no longer sees, and never touches Steam's own
          templates sitting in the same directory.
        '';
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            description = lib.mkOption {
              type = lib.types.str;
              default = "";
              description = "Blurb shown under the title in Steam.";
            };

            controllerType = lib.mkOption {
              type = lib.types.str;
              default = "controller_xbox360";
              description = ''
                Which controller the layout is written for. Steam's XInput type
                is the portable choice — it's what a DualShock, a DualSense or
                an Xbox pad all present as once Steam Input has them.
              '';
            };

            bindings = lib.mkOption {
              type = lib.types.attrsOf lib.types.str;
              default = {};
              example = lib.literalExpression ''
                {
                  button_a = "key_press RETURN";
                  button_y = "key_press F";
                }
              '';
              description = ''
                Physical input to Steam Input binding string.

                Inputs: button_a/b/x/y, dpad_north/south/east/west,
                left_stick_north/south/east/west, button_escape (Start),
                button_menu (Select), left_bumper, right_bumper,
                left_trigger, right_trigger.

                Bindings are Steam's own syntax, e.g. "key_press F",
                "mouse_button LEFT", "mouse_wheel SCROLL_UP".
              '';
            };
          };
        });
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [apply];

      # Same reasoning as steam-shortcuts: activation runs before any user
      # session exists, so Steam isn't up to race with.
      home.activation.steam-input =
        lib.hm.dag.entryAfter ["writeBoundary"] ''
          run ${apply}/bin/steam-input
        '';
    };
  };
}

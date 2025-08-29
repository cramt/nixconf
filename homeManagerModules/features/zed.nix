{
  pkgs,
  lib,
  ...
}: {
  programs.zed-editor = {
    enable = true;

    extensions = ["nix" "toml" "ruby"];

    userKeymaps = [
      {
        context = "GitPanel && ChangesList";
        bindings = {
          "space g s" = "git::ToggleStaged";
          "space g u" = "git::Restore";
        };
      }
      {
        bindings = {
          "space e" = "project_panel::ToggleFocus";
          "space g" = "git_panel::ToggleFocus";
        };
      }
      {
        context = "vim_mode == visual";
        bindings = {
          "space c" = "vim::ToggleComments";
        };
      }
      {
        context = "VimControl && !menu";
        bindings = {
          "down" = "vim::Down";
          "j" = "vim::Down";
          "left" = "vim::Left";
          "h" = "vim::Left";
          "right" = "vim::Right";
          "l" = "vim::Right";
          "up" = "vim::Up";
          "k" = "vim::Up";
        };
      }
      {
        context = "VimControl";
        bindings = {
          "space q" = "zed::Quit";
          "space l d" = "editor::GoToDefinition";
          "space l h" = "editor::Hover";
          "space s" = "workspace::Save";
          "space l a" = "editor::ToggleCodeActions";
          "space l shift-i" = "editor::GoToImplementation";
          "space l n" = "editor::Rename";
          "space l shift-a" = "editor::FindAllReferences";
          "space f s" = "outline::Toggle";
          "space f shift-s" = "project_symbols::Toggle";
          "space l y" = "editor::GoToTypeDefinition";
          "space l shift-d" = "editor::GoToDeclaration";
          "space c" = "pane::CloseActiveItem";
          "space shift-c" = "workspace::CloseInactiveTabsAndPanes";
          "shift h" = "workspace::ActivatePreviousPane";
          "shift l" = "workspace::ActivateNextPane";
          "f" = [
            "vim::PushFindForward"
            {
              before = false;
              multiline = true;
            }
          ];
          "shift-f" = [
            "vim::PushFindBackward"
            {
              after = false;
              multiline = true;
            }
          ];
        };
      }
    ];

    userSettings = {
      node = {
        path = lib.getExe pkgs.nodejs;
        npm_path = lib.getExe' pkgs.nodejs "npm";
      };

      hour_format = "hour24";
      auto_update = false;
      terminal = {
        alternate_scroll = "off";
        blinking = "off";
        copy_on_select = false;
        dock = "bottom";
        detect_venv = {
          on = {
            directories = [".env" "env" ".venv" "venv"];
            activate_script = "default";
          };
        };
        env = {
          TERM = "rio";
        };
        line_height = "comfortable";
        option_as_meta = false;
        button = false;
        shell = "system";
        working_directory = "current_project_directory";
      };

      lsp = {
        rust-analyzer = {
          binary = {
            path = lib.getExe pkgs.rust-analyzer;
          };
        };
        nix = {
          binary = {
            path = lib.getExe pkgs.nil;
          };
        };
      };

      vim_mode = true;
      load_direnv = "shell_hook";
      base_keymap = "VSCode";
      show_whitespaces = "none";
    };
  };
}

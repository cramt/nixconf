{
  pkgs,
  lib,
  inputs,
  ...
}: let
  rubyGems = (import ../../gems/default.nix) {
    pkgs = inputs.nixpkgs-ruby-downgrade.legacyPackages.${pkgs.system};
  };
in {
  programs.zed-editor = {
    enable = true;

    extensions = ["toml" "ruby" "rust" "nix" "terraform"];

    userKeymaps = [
      {
        context = "GitPanel && ChangesList";
        bindings = {
          "space g s" = "git::ToggleStaged";
          "space g u" = "git::Restore";
        };
      }
      {
        context = "!GitPanel && vim_mode == normal";
        bindings = {
          "space g" = "git_panel::ToggleFocus";
        };
      }
      {
        bindings = {
          "ctrl-t" = "terminal_panel::ToggleFocus";
        };
      }
      {
        context = "vim_mode == visual";
        bindings = {
          "space c" = "vim::ToggleComments";
          "tab" = "vim::Indent";
          "shift-tab" = "vim::Outdent";
        };
      }
      {
        context = "showing_code_actions || showing_completions";
        bindings = {
          "down" = "editor::ContextMenuNext";
          "j" = "editor::ContextMenuNext";
          "up" = "editor::ContextMenuPrevious";
          "k" = "editor::ContextMenuPrevious";
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
          "shift h" = "workspace::ActivatePreviousPane";
          "shift l" = "workspace::ActivateNextPane";
        };
      }
      {
        context = "VimControl && vim_mode == normal";
        bindings = {
          "space q" = "zed::Quit";
          "space w" = "workspace::Save";
          "space l d" = "editor::GoToDefinition";
          "space f f" = "file_finder::Toggle";
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
          "space e" = "project_panel::ToggleFocus";
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
      show_edit_predictions = false;
      journal.hour_format = "hour24";
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
      languages = {
        Nix.language_servers = ["nil"];
        Ruby.language_servers = ["ruby-lsp" "rubocop"];
      };
      lsp = {
        rust-analyzer.binary.path = lib.getExe pkgs.rust-analyzer;
        nil = {
          initialization_options.formatting.command = [(lib.getExe pkgs.alejandra) "--quiet" "--"];
          binary.path = lib.getExe pkgs.nil;
        };
        ruby-lsp.binary.path = lib.getExe rubyGems.ruby-lsp;
        rubocop.binary.path = lib.getExe rubyGems.rubocop;
      };

      vim_mode = true;
      load_direnv = "shell_hook";
      base_keymap = "VSCode";
      show_whitespaces = "none";
    };
  };
}

{ ... }: {
  hmModules.features.zed = { config, lib, pkgs, ... }: let
    rubyGems = (import ../../gems/default.nix) { inherit pkgs; };
    # JETLS formats by shelling out to runic, which nixpkgs doesn't package.
    # It runs formatters with its own JULIA_LOAD_PATH/JULIA_DEPOT_PATH, and a
    # devshell may set JULIA_PROJECT; the withPackages wrapper defers to all of
    # those, which drops Runic off the load path, so clear them first.
    runic = pkgs.writeShellScriptBin "runic" ''
      unset JULIA_LOAD_PATH JULIA_DEPOT_PATH JULIA_PROJECT
      exec ${pkgs.julia.withPackages ["Runic"]}/bin/julia --startup-file=no -m Runic "$@"
    '';
  in {
    options.myHomeManager.zed.enable = lib.mkEnableOption "myHomeManager.zed";
    config = lib.mkIf config.myHomeManager.zed.enable {
      # Neither of these is in Zed's extension registry, so the `extensions`
      # list below can't reach them. Symlinking the prebuilt artifacts into
      # Zed's installed-extension directory is equivalent to what
      # `zed: install dev extension` produces, minus the manual step and the
      # rustup/wasi-sdk downloads Zed would do at install time.
      # recursive, so the directory stays writable and Zed's index scan — which
      # is what actually registers the language — walks real files.
      home.file = lib.listToAttrs (map (ext:
        lib.nameValuePair ".local/share/zed/extensions/installed/${ext.extensionId}" {
          source = ext;
          recursive = true;
        }) [
        pkgs.zed-spade
        pkgs.zed-vixen
      ]);

      # On PATH rather than via JETLS's `formatter.custom`: JETLS (2026-10-08)
      # drops the settings from its initial workspace/configuration and only
      # applies them after a didChangeConfiguration, so after every start it
      # falls back to its default "Runic" preset, which looks up `runic` on PATH
      home.packages = [runic];

      programs.zed-editor = {
        enable = true;
        extensions = ["toml" "ruby" "rust" "nix" "terraform" "go" "java" "scala" "zig" "cpp" "make" "just" "sql" "dockerfile" "html" "css" "json-schema" "catppuccin" "styx" "julia" "vhdl" "markdown-oxide"];
        mutableUserSettings = false;
        mutableUserKeymaps = false;
        mutableUserTasks = false;
        mutableUserDebug = false;
        userKeymaps = [
          { context = "GitPanel && ChangesList"; bindings = { "space g s" = "git::ToggleStaged"; "space g u" = "git::Restore"; }; }
          { context = "!GitPanel && vim_mode == normal"; bindings = { "space g" = "git_panel::ToggleFocus"; }; }
          { bindings = { "ctrl-t" = "terminal_panel::ToggleFocus"; }; }
          { context = "vim_mode == visual"; bindings = { "space c" = "vim::ToggleComments"; "tab" = "vim::Indent"; "shift-tab" = "vim::Outdent"; }; }
          { context = "showing_code_actions || showing_completions"; bindings = { "down" = "editor::ContextMenuNext"; "tab" = "editor::ContextMenuNext"; "up" = "editor::ContextMenuPrevious"; "shift-tab" = "editor::ContextMenuPrevious"; }; }
          { context = "VimControl && !menu"; bindings = { "down" = "vim::Down"; "j" = "vim::Down"; "left" = "vim::Left"; "h" = "vim::Left"; "right" = "vim::Right"; "l" = "vim::Right"; "up" = "vim::Up"; "k" = "vim::Up"; }; }
          { context = "VimControl"; bindings = { "shift h" = "workspace::ActivatePreviousPane"; "shift l" = "workspace::ActivateNextPane"; }; }
          { context = "VimControl && vim_mode == normal"; bindings = {
            "space q" = "zed::Quit"; "space w" = "workspace::Save"; "space l d" = "editor::GoToDefinition";
            "space f f" = "file_finder::Toggle"; "space l h" = "editor::Hover"; "space s" = "workspace::Save";
            "space l a" = "editor::ToggleCodeActions"; "space l shift-i" = "editor::GoToImplementation";
            "space l n" = "editor::Rename"; "space l shift-a" = "editor::FindAllReferences";
            "space f s" = "outline::Toggle"; "space f shift-s" = "project_symbols::Toggle";
            "space l y" = "editor::GoToTypeDefinition"; "space l shift-d" = "editor::GoToDeclaration";
            "space c" = "pane::CloseActiveItem"; "space shift-c" = "workspace::CloseInactiveTabsAndPanes";
            "space e" = "project_panel::ToggleFocus";
            "f" = [ "vim::PushFindForward" { before = false; multiline = true; } ];
            "shift-f" = [ "vim::PushFindBackward" { after = false; multiline = true; } ];
          }; }
        ];
        userSettings = {
          node = { path = lib.getExe pkgs.nodejs; npm_path = lib.getExe' pkgs.nodejs "npm"; };

          journal.hour_format = "hour24";
          auto_update = false;
          terminal = {
            alternate_scroll = "off"; blinking = "off"; copy_on_select = false; dock = "bottom";
            detect_venv = { on = { directories = [".env" "env" ".venv" "venv"]; activate_script = "default"; }; };
            env = { TERM = "xterm-256color"; };
            line_height = "comfortable"; option_as_meta = false; button = false; shell = "system";
            working_directory = "current_project_directory";
          };
          languages = {
            Nix.language_servers = ["nil"];
            Ruby.language_servers = ["ruby-lsp" "rubocop"];
            # vhdl_ls has no documentFormattingProvider; vhdl_lang ships alongside it
            # and formats a path to stdout, so /dev/stdin makes it a pipe filter
            VHDL.formatter.external = {
              command = lib.getExe' pkgs.vhdl-ls "vhdl_lang";
              arguments = ["--format" "/dev/stdin"];
            };
          };
          lsp = {
            rust-analyzer.binary.path = lib.getExe pkgs.rust-analyzer;
            nil = {
              initialization_options = {
                nix.flake.autoArchive = true;
                formatting.command = [(lib.getExe pkgs.alejandra) "--quiet" "--"];
              };
              binary.path = lib.getExe pkgs.nil;
            };
            ruby-lsp.binary.path = lib.getExe rubyGems.ruby-lsp;
            rubocop.binary.path = lib.getExe rubyGems.rubocop;
            # wikilinks, backlinks and rename across a folder of notes, so Zed works as an Obsidian-style notes editor
            markdown-oxide.binary.path = lib.getExe pkgs.markdown-oxide;
          };

          project_panel.dock = "left";
          git_panel.dock = "left";
          outline_panel.dock = "left";

          theme = lib.mkForce "Catppuccin Mocha";
          vim_mode = true;
          load_direnv = "shell_hook";
          base_keymap = "VSCode";
          show_whitespaces = "none";
        };
      };
    };
  };
}

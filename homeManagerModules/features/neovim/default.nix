{ pkgs, inputs, lib, ... }:
let
  toLua = str: "lua << EOF\n${str}\nEOF\n";
  toLuaFile = file: toLua (builtins.readFile file);
in

{
  config = {
    stylix.targets.nixvim.enable = true;
    xdg.configFile."neovide/config.toml".source = ./neovide_config.toml;
    home.packages = with pkgs; [
      neovide
    ];

    programs.nixvim = {
      enable = true;
      extraConfigLua = ''
        ${builtins.readFile ./config.lua}
      '';
      globals = {
        mapleader = " ";
        neovide_transparency = 0.8;
        guifont = "Iosevka Nerd Font";
      };
      globalOpts = {
        fillchars = {
          eob = " ";
        };
        number = true;
        shiftwidth = 4;
        tabstop = 4;
        preserveindent = true;
        copyindent = true;
        expandtab = true;
        showmode = false;
        signcolumn = "yes";
      };
      clipboard = {
        providers.wl-copy.enable = true;
        register = "unnamedplus";
      };
      extraPlugins = with pkgs.vimPlugins; [
        # we wanna setup this manually
        # aka not with nixvim
        # cause it breaks neovide transparency
        {
          plugin = transparent-nvim;
          config = toLua ''
            if not vim.g.neovide then
              vim.g.transparent_enabled = true
              require("transparent").setup({})
            end
          '';
        }

      ];
      userCommands =
        let
          searchAndReplaceAliases = {
            NewLineRemove = [
              ''/\([^\s]\)\-\n/\1/''
              ''/\n/ /''
            ];
          };
        in
        builtins.mapAttrs
          (name: value: {
            command = (
              lib.strings.concatStringsSep " | " (
                builtins.map (regex: "'<,'>s${regex}e") value
              )
            ) + " | noh";
            range = true;
          })
          searchAndReplaceAliases;
      keymaps = ((import ./keymaps.nix) {
        inherit lib;
      }).keymaps;
      plugins = (import ./plugins.nix) {
        inherit pkgs;
        inherit inputs;
        inherit lib;
      };
    };
  };
}


{ pkgs, inputs, ... }:
let
  toLua = str: "lua << EOF\n${str}\nEOF\n";
in
{
  config = {
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
      };
      globalOpts = {
        fillchars = {
          eob = " ";
        };
        number = true;

      };
      clipboard = {
        providers.wl-copy.enable = true;
        register = "unnamedplus";
      };
      keymaps = [
        {
          mode = "n";
          key = "<Leader>w";
          action = "<Cmd>w<CR>";
          options = {
            desc = "save";
          };
        }
        {
          mode = "n";
          key = "<leader>q";
          action = "<cmd>confirm q<cr>";
          options = {
            desc = "quit window";
          };
        }
        {
          mode = "n";
          key = "<leader>Q";
          action = "<cmd>confirm qall<cr>";
          options = {
            desc = "quit neovim";
          };
        }
        {
          mode = "n";
          key = "<leader>e";
          action = "<Cmd>Neotree toggle<CR>";
          options = {
            desc = "Toggle explorer";
          };
        }
        {
          mode = "v";
          key = "<Tab>";
          action = ">gv";
        }
        {
          mode = "v";
          key = "<S-Tab>";
          action = "<gv";
        }
      ];
      plugins = {
        lsp = {
          enable = true;
          servers = {
            nil_ls = {
              enable = true;
              settings = {
                formatting = {
                  command = [ "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt" ];
                };
              };
            };
            solargraph.enable = true;
          };
        };
        neorg = {
          enable = true;
          modules = {
            "core.defaults" = {
              __empty = null;
            };
            "core.dirman" = {
              config = {
                workspaces = {
                  notes = "~/notes";
                };
              };
            };
          };
        };
        lsp-format = {
          enable = true;
        };
        lsp-lines = {
          enable = true;
        };
        # TODO: switch to airline once the themeing works
        bufferline = {
          enable = true;
        };
        treesitter = {
          enable = true;
        };
        cmp = {
          enable = true;
        };
        neo-tree = {
          enable = true;
        };
        which-key = {
          enable = true;
        };
        cmp-nvim-lsp = {
          enable = true;
        };
        telescope = {
          enable = true;
          extraOptions = {
            pickers = {
              find_files = {
                theme = "ivy";
              };
            };
          };
          keymaps = {
            "<Leader>ff" = {
              mode = "n";
              action = "find_files";
              options = {
                desc = "Find files";
              };
            };
          };
        };
      };
    };
  };
}


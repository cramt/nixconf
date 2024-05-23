{ pkgs, ... }:
let
  toLua = str: "lua << EOF\n${str}\nEOF\n";
  toLuaFile = file: toLua (builtins.readFile file);
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
        shiftwidth = 2;
        tabstop = 2;
        expandtab = true;
        showmode = false;
      };
      clipboard = {
        providers.wl-copy.enable = true;
        register = "unnamedplus";
      };
      keymaps = [
        {
          mode = "n";
          key = "<Leader>l";
          action = "";
          options = {
            desc = "LSP";
          };
        }
        {
          mode = "n";
          key = "<Leader>la";
          lua = true;
          action = ''
            function() vim.lsp.buf.code_action() end
          '';
          options = {
            desc = "LSP code action";
            #cond = "testDocument/codeAction";
          };
        }
        {
          mode = "n";
          key = "<Leader>lr";
          lua = true;
          action = ''
            function() vim.lsp.buf.rename() end
          '';
          options = {
            desc = "LSP rename";
            #cond = "testDocument/rename";
          };
        }
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
          key = "L";
          action = "<cmd>bnext<cr>";
          options = {
            desc = "next buffer";
          };
        }
        {
          mode = "n";
          key = "H";
          action = "<cmd>bprev<cr>";
          options = {
            desc = "previous buffer";
          };
        }
        {
          mode = "n";
          key = "<leader>e";
          lua = true;
          action = ''
            function()
            	if vim.bo.filetype == "neo-tree" then
            		vim.cmd.wincmd "p"
            	else
            		vim.cmd.Neotree "focus"
            	end
            end
          '';
          options = {
            desc = "Open explorer";
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
            lua-ls.enable = true;
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
        fugitive = {
          enable = true;
        };
        lualine = {
          enable = true;
          globalstatus = true;
          sections = {
            lualine_x = [ "filetype" ];
          };
          tabline = {
            lualine_a = [
              {
                name = "buffers";
                extraConfig = {
                  symbols = {
                    modified = "●";
                    directory = "";
                    alternate_file = "";
                  };
                };
              }
            ];
          };
        };
        treesitter = {
          enable = true;
        };
        neo-tree = {
          enable = true;
          buffers = {
            followCurrentFile = {
              enabled = true;
              leaveDirsOpen = true;
            };
          };
          filesystem = {
            followCurrentFile = {
              enabled = true;
              leaveDirsOpen = true;
            };
            filteredItems = {
              visible = false;
              hideDotfiles = false;
              hideGitignored = true;
              hideByPattern = [ ".git" ];
            };
          };
        };
        which-key = {
          enable = true;
        };
        cmp = {
          enable = true;
          settings = {
            sources = [
              {
                name = "nvim_lsp";
              }
              {
                name = "buffer";
              }
            ];
            mapping = {
              "<C-Space>" = "cmp.mapping.complete()";
              "<C-d>" = "cmp.mapping.scroll_docs(-4)";
              "<C-e>" = "cmp.mapping.close()";
              "<C-f>" = "cmp.mapping.scroll_docs(4)";
              "<CR>" = "cmp.mapping.confirm({ select = true })";
              "<S-Tab>" = "cmp.mapping(cmp.mapping.select_prev_item(), {'i', 's'})";
              "<Tab>" = "cmp.mapping(cmp.mapping.select_next_item(), {'i', 's'})";
            };
          };
        };
        cmp-nvim-lsp = {
          enable = true;
        };
        cmp-buffer = {
          enable = true;
        };
        telescope = {
          enable = true;
          extensions.fzf-native.enable = true;
          extraOptions = {
            pickers = {
              find_files = {
                theme = "ivy";
              };
              live_grep = {
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

            "<Leader>fw" = {
              mode = "n";
              action = "live_grep";
              options = {
                desc = "Find by words";
              };
            };
          };
        };
      };
    };
  };
}


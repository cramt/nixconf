{ pkgs, ... }: {
  config = {
    xdg.configFile."neovide/config.toml".source = ./neovide_config.toml;
    home.packages = with pkgs; [
      neovide
    ];

    programs.nixvim = {
      enable = true;
      globals = {
        mapleader = " ";
        neovide_transparency = 0.8;
        number = true;
      };
      globalOpts = {
	fillchars = {
	  eob = " ";
        };
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
      ];
      plugins = {
        lsp = {
          enable = true;
          servers = {
            nil_ls.enable = true;
            solargraph.enable = true;
          };
        };
	lsp-format = {
	  enable = true;
	};
	lsp-lines= {
	  enable = true;
	};
        bufferline = {
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


{ pkgs, inputs, lib }: {
  mini = {
    enable = true;
    modules = {
      bufremove = { };
    };
  };
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
      solargraph = {
        enable = true;
        package = inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.rubyPackages.solargraph;
      };
      lua-ls.enable = true;
      sqls.enable = true;
      yamlls.enable = true;
      terraformls.enable = true;
      gopls.enable = true;
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
      hijackNetrwBehavior = "open_current";
    };
  };
  which-key = {
    enable = true;
    registrations = ((import ./keymaps.nix) {
      inherit lib;
    }).keymapGroups;
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
  cmp_luasnip = {
    enable = true;
  };
  luasnip = {
    enable = true;
    package = inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.vimPlugins.luasnip;
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
}

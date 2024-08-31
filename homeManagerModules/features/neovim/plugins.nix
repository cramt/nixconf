{ pkgs, inputs, lib }: {
  mini = {
    enable = true;
    modules = {
      bufremove = { };
    };
  };
  none-ls = {
    enable = true;
    enableLspFormat = true;
    sources = {
      formatting = {
        prettier.enable = true;
        prettier.disableTsServerFormatter = true;
        just.enable = true;
        terraform_fmt.enable = true;
        rubocop = {
          enable = false;
          package = inputs.nixpkgs-ruby-downgrade.legacyPackages.${pkgs.system}.rubyPackages.rubocop;
        };
      };
      diagnostics = {
        actionlint.enable = true;
      };
    };
  };
  lspsaga = {
    enable = true;
    lightbulb.virtualText = false;
  };
  lsp = {
    enable = true;
    servers = {
      nil-ls = {
        enable = true;
        settings = {
          formatting = {
            command = [ "${pkgs.nixpkgs-fmt}/bin/nixpkgs-fmt" ];
          };
        };
      };
      solargraph = {
        enable = false;
        package = inputs.nixpkgs-ruby-downgrade.legacyPackages.${pkgs.system}.rubyPackages.solargraph;
      };
      ruby-lsp = {
        enable = true;
        package = inputs.nixpkgs-ruby-downgrade.legacyPackages.${pkgs.system}.rubyPackages.ruby-lsp;
        extraOptions = {
          rubyLsp = {
            rubyVersionManager = "custom";
            customRubyCommand = "";
          };
        };
      };
      lua-ls.enable = true;
      sqls.enable = false;
      yamlls.enable = true;
      terraformls.enable = true;
      gopls.enable = true;
      tsserver.enable = true;
      #todo: fix with https://nixpk.gs/pr-tracker.html?pr=335559
      #eslint.enable = true;
      astro.enable = true;
      rust-analyzer = {
        enable = true;
        installCargo = true;
        installRustc = true;
      };
    };
  };
  neorg = {
    enable = true;
    modules =
      let
        empty = { __empty = null; };
      in
      {
        "core.defaults" = empty;
        "core.concealer" = empty;
        "core.export" = empty;
        "core.summary" = empty;
        "core.keybinds" = empty;
        "core.completion" = {
          config = {
            engine = "nvim-cmp";
          };
        };
        "core.journal" = empty;
        "core.dirman" = {
          config = {
            workspaces = {
              notes = "~/notes";
            };
            default_workspace = "notes";
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
    # treesitter is packaged inside neovim now, maybe this will be fixed in nixvim in future
    #enable = true;
    settings.highlight.enable = true;
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
    settings.spec = lib.attrsets.mapAttrsToList
      (name: value: (lib.attrsets.filterAttrs (n: v: n != "action") value) // {
        __unkeyed-1 = name;
        __unkeyed-2 = value.action;
      })
      ((import ./keymaps.nix) {
        inherit lib;
      }).keymap;
  };
  cmp = {
    enable = true;
    autoEnableSources = true;
    settings = {
      sources = builtins.map (x: { name = x; }) [
        "nvim_lsp"
        "buffer"
        "path"
        "vsnip"
        "neorg"
        "otter"
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
  cmp-vsnip.enable = true;
  telescope = {
    enable = true;
    extensions.fzf-native.enable = true;
    settings = {
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
  firenvim = {
    enable = true;
  };
}

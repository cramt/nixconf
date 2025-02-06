{
  pkgs,
  inputs,
  lib,
}: let
  rubyGems = (import ../../../gems/default.nix) {
    pkgs = inputs.nixpkgs-ruby-downgrade.legacyPackages.${pkgs.system};
  };
in {
  mini = {
    enable = true;
    modules = {
      bufremove = {};
    };
  };
  none-ls = {
    enable = true;
    sources = {
      formatting = {
        prettier = {
          enable = true;
          disableTsServerFormatter = true;
          settings.disabled_filetypes = ["astro"]; # for some reason this fucks up astro
        };
        just.enable = true;
        terraform_fmt = {
          enable = true;
          package = pkgs.terraform;
        };
        rubocop = {
          enable = false;
          package = rubyGems.rubocop;
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
      nixd = {
        enable = true;
        settings = {
          formatting = {
            command = ["${pkgs.alejandra}/bin/alejandra"];
          };
        };
      };
      ruby_lsp = {
        enable = true;
        package = rubyGems.ruby-lsp;
        extraOptions = {
          rubyLsp = {
            rubyVersionManager = "custom";
            customRubyCommand = "";
          };
        };
      };
      tailwindcss = {
        enable = true;
        filetypes = ["rust"];
        extraOptions = {
          tailwindCSS = {
            includeLanguages = {
              rust = "html";
            };
            experimental.classRegex = [''class: "(.*)"''];
          };
        };
      };
      lua_ls.enable = true;
      sqls.enable = false;
      yamlls.enable = true;
      terraformls.enable = true;
      gopls.enable = true;
      ts_ls.enable = true;
      eslint.enable = true;
      astro.enable = true;
      arduino_language_server = {
        enable = true;
        cmd = [
          "${pkgs.arduino-language-server}/bin/arduino-language-server"
          "-clangd"
          "${pkgs.libclang}/bin/clangd"
          "-cli"
          "${pkgs.arduino-cli}/bin/arduino-cli"
          "-cli-config"
          "$ARDUINO_CONFIG_FILE"
          "-fqbn"
          "$ARDUINO_FQBN"
        ];
      };
    };
  };
  rustaceanvim = {
    enable = true;
  };
  neorg = {
    enable = true;
    settings.load = let
      empty = {__empty = null;};
    in {
      "core.defaults" = empty;
      "core.concealer" = empty;
      "core.export" = empty;
      "core.export.markdown" = {
        config = {
          extensions = ["metadata"];
        };
      };
      "core.esupports.metagen" = {
        config = {
          type = "auto";
          template = [
            ["title"]
            ["description" "empty"]
            ["authors"]
            ["categories" "[]"]
            ["created"]
            ["updated"]
            ["version"]
          ];
        };
      };
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
    settings = {
      options = {
        globalstatus = true;
      };
      sections = {
        lualine_x = ["filetype"];
      };
      tabline = {
        lualine_a = [
          {
            __unkeyed-1 = "buffers";
            symbols = {
              modified = "●";
              directory = "";
              alternate_file = "";
            };
          }
        ];
      };
    };
  };
  treesitter = {
    enable = true;
    settings.highlight.enable = true;
  };
  web-devicons = {
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
        hideByPattern = [".git"];
      };
      hijackNetrwBehavior = "open_current";
    };
  };
  which-key = {
    enable = true;
    settings.spec =
      lib.attrsets.mapAttrsToList
      (name: value:
        (lib.attrsets.filterAttrs (n: v: n != "action") value)
        // {
          __unkeyed-1 = name;
          __unkeyed-2 = value.action;
        })
      ((import ./keymaps.nix) {
        inherit lib;
      })
      .keymap;
  };
  cmp = {
    enable = true;
    autoEnableSources = true;
    settings = {
      sources = builtins.map (x: {name = x;}) [
        "nvim_lsp"
        "buffer"
        "path"
        "vsnip"
        "neorg"
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
}

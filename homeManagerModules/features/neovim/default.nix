{
  pkgs,
  config,
  inputs,
  lib,
  ...
}: let
  rubyGems = (import ../../../gems/default.nix) {
    pkgs = inputs.nixpkgs-ruby-downgrade.legacyPackages.${pkgs.system};
  };
in {
  config = {
    stylix.targets.nixvim.enable = true;
    home.packages = [
      pkgs.obsidian
    ];

    home.file."empty-obsidian-workspace" = {
      source = ../../../empty_obsidian_workspace;
      recursive = true;
    };

    programs.neovide = {
      enable = true;
      settings = {
        fork = true;
        frame = "none";
        vsync = false;
      };
    };

    stylix.targets.nvf = {
      enable = true;
      transparentBackground = true;
    };

    home.sessionVariables = {
      GEMINI_API_KEY = (import ../../../secrets.nix).gemini_api_key;
    };

    programs.nvf = {
      enable = true;
      settings = {
        vim = {
          assistant = {
            avante-nvim = {
              enable = true;
              setupOpts = {
                provider = "gemini";
                providers = {
                  gemini = {
                    model = "gemini-2.0-flash";
                  };
                };
              };
            };
          };

          luaConfigRC.no_fill_chars =
            # lua
            ''
              vim.opt.fillchars = {
                eob = ' ',
              }
              vim.opt.shiftwidth = 4;
              vim.opt.tabstop = 4;
            '';
          globals = {
            neovide_opacity = 0.8;
            guifont = "Iosevka Nerd Font";
          };
          viAlias = true;
          vimAlias = true;
          lineNumberMode = "number";

          clipboard = {
            enable = true;
            registers = "unnamedplus";
          };

          debugMode = {
            enable = false;
            level = 16;
            logFile = "/tmp/nvim.log";
          };

          spellcheck = {
            enable = true;
          };

          keymaps =
            [
              {
                key = "<leader>w";
                mode = "n";
                action = "<Cmd>w<CR>";
                desc = "Save";
              }
              {
                key = "<leader>q";
                mode = "n";
                action = "<Cmd>confirm q<CR>";
                desc = "Quit";
              }
              {
                key = "<leader>Q";
                mode = "n";
                action = "<Cmd>confirm qall<CR>";
                desc = "Quit all";
              }
              {
                key = "<leader>c";
                mode = "n";
                action = ''
                  function()
                    require("bufdelete").bufdelete(vim.api.nvim_get_current_buf(), false)
                  end
                '';
                lua = true;
                desc = "Close buffer";
              }
              {
                key = "<leader>C";
                mode = "n";
                action = ''
                  function()
                    require("bufdelete").bufdelete(vim.api.nvim_get_current_buf(), true)
                  end
                '';
                lua = true;
                desc = "Force close buffer";
              }
              {
                key = "L";
                mode = "n";
                action = "<Cmd>bnext<CR>";
                desc = "Next Buffer";
              }
              {
                key = "H";
                mode = "n";
                action = "<Cmd>bprev<CR>";
                desc = "Prev Buffer";
              }
              {
                key = "<C-Left>";
                mode = "n";
                action = ":vertical resize -5<CR>";
                desc = "Resize Left";
              }
              {
                key = "<C-Right>";
                mode = "n";
                action = ":vertical resize +5<CR>";
                desc = "Resize Right";
              }
              {
                key = "<leader>e";
                mode = "n";
                action = ''
                  function()
                    if vim.bo.filetype == "neo-tree" then
                      vim.cmd.wincmd "p"
                    else
                      vim.cmd.Neotree "focus"
                    end
                  end
                '';
                lua = true;
                desc = "Open exlorer";
              }
              {
                key = "<Tab>";
                mode = "v";
                action = ">gv";
                desc = "Indent";
              }
              {
                key = "<S-Tab>";
                mode = "v";
                action = "<gv";
                desc = "Unindent";
              }
            ]
            ++ (builtins.map (x: {
              key = "<C-${lib.strings.toUpper x}>";
              mode = "n";
              action = "<C-W>${x}";
            }) ["h" "j" "k" "l"]);

          lsp = {
            enable = true;
            null-ls.setupOpts.default_timeout = 10000;
            formatOnSave = true;
            lspkind.enable = false;
            lightbulb.enable = true;
            lspsaga.enable = false;
            trouble.enable = true;
            lspSignature.enable = true;
            otter-nvim.enable = true;
            nvim-docs-view.enable = true;
            lspconfig.sources.sourcekit = ''
              lspconfig.sourcekit.setup {
                capabilities = capabilities,
                on_attach = default_on_attach,
                cmd = { "${pkgs.sourcekit-lsp}/bin/sourcekit-lsp" }
              }
            '';
            lspconfig.sources.futhark_lsp = ''
              lspconfig.futhark_lsp.setup {
                capabilities = capabilities,
                on_attach = default_on_attach,
                cmd = { "${pkgs.futhark}/bin/futhark", "lsp", "--stdio" }
              }
            '';
          };

          fzf-lua.profile = "fzf-native";

          debugger = {
            nvim-dap = {
              enable = true;
              ui.enable = true;
            };
          };

          languages = {
            enableFormat = true;
            enableTreesitter = true;
            enableExtraDiagnostics = true;
            nix.enable = true;
            zig.enable = true;
            markdown.enable = true;
            bash.enable = true;
            julia = {
              enable = true;
              lsp.package = pkgs.julia;
            };
            clang.enable = true;
            css.enable = true;
            html.enable = true;
            sql.enable = false;
            go.enable = true;
            lua.enable = true;
            terraform.enable = true;
            rust = {
              enable = true;
              crates.enable = true;
            };
            astro.enable = true;
            nu.enable = true;
            tailwind.enable = true;
            ts = {
              enable = true;
              extensions.ts-error-translator.enable = true;
              extraDiagnostics.enable = true;
            };
            ruby = {
              enable = true;
              lsp.server = "rubylsp";
              lsp.package = rubyGems.ruby-lsp;
              format.package = rubyGems.rubocop;
            };
          };

          visuals = {
            nvim-scrollbar.enable = true;
            nvim-web-devicons.enable = true;
            nvim-cursorline.enable = true;
            cinnamon-nvim.enable = true;
            fidget-nvim.enable = true;

            highlight-undo.enable = true;
            indent-blankline.enable = true;

            # Fun
            cellular-automaton.enable = false;
          };

          statusline = {
            lualine = {
              enable = true;
              theme = "base16";
            };
          };

          autopairs.nvim-autopairs.enable = true;

          autocomplete.nvim-cmp.enable = true;
          snippets.luasnip.enable = true;

          filetree = {
            neo-tree = {
              enable = true;
              setupOpts = {
                buffers = {
                  follow_current_file = {
                    enabled = true;
                    leave_dirs_open = true;
                  };
                };
                filesystem = {
                  follow_current_file = {
                    enabled = true;
                    leave_dirs_open = true;
                  };
                  hijack_netrw_behavior = "open_current";
                  filtered_items = {
                    visible = false;
                    hide_dotfiles = false;
                    hide_gitignored = true;
                    hide_by_pattern = [".git" ".jj"];
                  };
                };
              };
            };
          };

          tabline = {
            nvimBufferline.enable = true;
          };

          treesitter = {
            grammars = [pkgs.tree-sitter-grammars.tree-sitter-norg-meta];
            context.enable = true;
          };

          binds = {
            whichKey.enable = true;
            cheatsheet.enable = true;
          };

          telescope.enable = true;

          git = {
            enable = true;
            gitsigns.enable = true;
            gitsigns.codeActions.enable = false; # throws an annoying debug message
          };

          minimap = {
            minimap-vim.enable = false;
            codewindow.enable = true; # lighter, faster, and uses lua for configuration
          };

          dashboard = {
            dashboard-nvim.enable = false;
            alpha.enable = true;
          };

          notify = {
            nvim-notify.enable = true;
          };

          projects = {
            project-nvim.enable = true;
          };

          utility = {
            ccc.enable = false;
            vim-wakatime.enable = false;
            icon-picker.enable = true;
            surround.enable = true;
            diffview-nvim.enable = true;
            yanky-nvim.enable = false;
            motion = {
              hop.enable = true;
              leap.enable = true;
              precognition.enable = true;
            };

            images = {
              image-nvim.enable = false;
            };
          };

          notes = {
            obsidian = {
              enable = true;
              setupOpts = {
                workspaces = [
                  {
                    name = "_default";
                    path = "~/empty-obsidian-workspace";
                  }
                ];
              };
            };
            neorg = {
              enable = false;
              setupOpts.load = {
                "core.defaults".enable = true;
                "core.concealer".enable = true;
                "core.export".enable = true;
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
                "core.summary".enable = true;
                "core.keybinds".enable = true;
                "core.completion" = {
                  config = {
                    engine = "nvim-cmp";
                  };
                };
                "core.journal".enable = true;
                "core.dirman" = {
                  config = {
                    workspaces = {
                      notes = "~/notes";
                    };
                  };
                };
              };
            };
          };

          terminal = {
            toggleterm = {
              enable = true;
              lazygit.enable = true;
            };
          };

          ui = {
            borders.enable = true;
            noice.enable = true;
            colorizer.enable = true;
            modes-nvim.enable = false; # the theme looks terrible with catppuccin
            illuminate.enable = true;
            breadcrumbs = {
              enable = true;
              navbuddy.enable = true;
            };
            smartcolumn = {
              enable = true;
              setupOpts.custom_colorcolumn = {
                # this is a freeform module, it's `buftype = int;` for configuring column position
                nix = "110";
                ruby = "120";
                java = "130";
                go = ["90" "130"];
              };
            };
            fastaction.enable = true;
          };

          assistant = {
            codecompanion-nvim = {
              enable = true;
              setupOpts = {
                adapters =
                  lib.generators.mkLuaInline
                  # lua
                  ''
                    {
                      l = function ()
                        return require("codecompanion.adapters").extend("ollama", {
                          name = "l",
                          schema = {
                            model = {
                              default = "qwen2.5-coder:3b",
                            }
                          }
                        })
                      end
                    }
                  '';
                strategies = {
                  chat.adapter = "l";
                  inline.adapter = "l";
                };
                display.diff.provider = "mini_diff";
              };
            };
            chatgpt.enable = false;
            copilot = {
              enable = false;
              cmp.enable = false;
            };
          };

          mini.diff.enable = true;

          session = {
            nvim-session-manager.enable = false;
          };

          gestures = {
            gesture-nvim.enable = false;
          };

          comments = {
            comment-nvim.enable = true;
          };

          presence = {
            neocord.enable = false;
          };
        };
      };
    };
  };
}

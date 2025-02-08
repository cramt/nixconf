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
    xdg.configFile."neovide/config.toml".source = ./neovide_config.toml;
    home.packages = [
      pkgs.neovide
    ];

    programs.nvf = {
      enable = true;
      settings = {
        vim = {
          luaConfigRC.no_fill_chars =
            # lua
            ''
              vim.opt.fillchars = {
                eob = ' ',
              }
            '';
          globals = {
            neovide_transparency = 0.8;
            guifont = "Iosevka Nerd Font";
          };
          viAlias = true;
          vimAlias = true;
          lineNumberMode = "number";

          useSystemClipboard = true;

          debugMode = {
            enable = false;
            level = 16;
            logFile = "/tmp/nvim.log";
          };

          spellcheck = {
            enable = true;
          };

          keymaps = [
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
          ];

          lsp = {
            formatOnSave = true;
            lspkind.enable = false;
            lightbulb.enable = true;
            lspsaga.enable = false;
            trouble.enable = true;
            lspSignature.enable = true;
            otter-nvim.enable = true;
            lsplines.enable = true;
            nvim-docs-view.enable = true;
            lspconfig.sources.ruby-lsp = ''
              lspconfig.ruby_lsp.setup {
                capabilities = capabilities,
                on_attach = attach_keymaps,
                cmd = { "${rubyGems.ruby-lsp}/bin/ruby-lsp" }
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

          # This section does not include a comprehensive list of available language modules.
          # To list all available language module options, please visit the nvf manual.
          languages = {
            enableLSP = true;
            enableFormat = true;
            enableTreesitter = true;
            enableExtraDiagnostics = true;
            nix.enable = true;
            markdown.enable = true;
            bash.enable = true;
            clang.enable = true;
            css.enable = true;
            html.enable = true;
            sql.enable = false;
            go.enable = true;
            lua.enable = true;
            rust = {
              enable = true;
              crates.enable = true;
            };
            astro.enable = true;
            nu.enable = true;
            tailwind.enable = true;
            ts = {
              enable = true;
              extraDiagnostics.enable = true;
            };
            ruby = {
              enable = true;
              lsp.enable = false;
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

          theme = {
            enable = true;
            name = "base16";
            style = "dark";
            base16-colors = {
              inherit (config.lib.stylix.colors) base00 base01 base02 base03 base04 base05 base06 base07 base08 base09 base0A base0B base0C base0D base0E base0F;
            };
            transparent = true;
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

          treesitter.context.enable = true;

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
              enable = false;
            };
            neorg = {
              enable = true;
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
            chatgpt.enable = false;
            copilot = {
              enable = false;
              cmp.enable = false;
            };
          };

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

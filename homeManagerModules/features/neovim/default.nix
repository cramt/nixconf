{
  pkgs,
  config,
  lib,
  ...
}: {
  config = {
    stylix.targets.nixvim.enable = true;

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
              vim.opt.shiftwidth = 4;
              vim.opt.tabstop = 4;

              -- Transparent background (let terminal opacity show through)
              -- Skip in neovide since it handles its own opacity
              if not vim.g.neovide then
                local groups = {
                  "Normal", "NormalFloat", "NormalNC",
                  "SignColumn", "LineNr", "CursorLineNr",
                  "EndOfBuffer", "FloatBorder", "WinSeparator",
                }
                for _, group in ipairs(groups) do
                  local hl = vim.api.nvim_get_hl(0, { name = group })
                  hl.bg = nil
                  vim.api.nvim_set_hl(0, group, hl)
                end
              end
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

          fzf-lua.profile = "fzf-native";

          languages = {
            enableTreesitter = true;
            enableExtraDiagnostics = false;
            markdown.enable = true;
            bash.enable = true;
            css.enable = true;
            html.enable = true;
            rust = {
              enable = true;
            };
            astro.enable = true;
            tailwind.enable = true;
            ts = {
              enable = true;
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
          };

          statusline = {
            lualine = {
              enable = true;
              theme = "base16";
            };
          };

          autopairs.nvim-autopairs.enable = true;

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
            codewindow.enable = false; # broken: uses removed nvim-treesitter.ts_utils API
          };

          dashboard = {
            dashboard-nvim.enable = false;
            alpha.enable = true;
          };

          notify = {
            nvim-notify.enable = true;
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
            modes-nvim.enable = false;
            illuminate.enable = true;
          };

          assistant = {
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

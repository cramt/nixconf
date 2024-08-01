{ lib }:
let
  keymaptree = {
    n = {
      "<Leader>" = {
        children = {
          l = {
            desc = "LSP";
            children = {
              a = {
                desc = "code action";
                action = "<Cmd>Lspsaga code_action<CR>";
                cond = "textDocument/codeaction";
              };
              r = {
                desc = "rename";
                action = "<Cmd>Lspsaga rename<CR>";
                cond = "textDocument/rename";
              };
              c = {
                desc = "incomming calls";
                action = "<Cmd>Lspsaga incomming_calls<CR>";
                cond = "callHierarchy/incomingCalls";
              };
              C = {
                desc = "outgoing calls";
                action = "<Cmd>Lspsaga outgoing_calls<CR>";
                cond = "callHierarchy/outgoingCalls";
              };
              h = {
                desc = "hover docs";
                action = "<Cmd>Lspsaga hover_doc<CR>";
                cond = "textDocument/hover";
              };
              d = {
                desc = "definition";
                children = {
                  p = {
                    desc = "peek";
                    action = "<Cmd>Lspsaga peek_definition<CR>";
                    cond = "textDocument/definition";
                  };
                  g = {
                    desc = "goto";
                    action = "<Cmd>Lspsaga goto_definition<CR>";
                    cond = "textDocument/definition";
                  };
                };
              };
            };
          };
          w = {
            desc = "save";
            action = "<Cmd>w<CR>";
          };
          q = {
            desc = "quit window";
            action = "<Cmd>confirm q<CR>";
          };
          Q = {
            desc = "quit neovim";
            action = "<Cmd>confirm qall<CR>";
          };
          e = {
            desc = "open explorer";
            action.__raw = ''
              function()
                if vim.bo.filetype == "neo-tree" then
                  vim.cmd.wincmd "p"
                else
                  vim.cmd.Neotree "focus"
                end
              end
            '';
          };
          b = {
            desc = "Buffers";
            children = {
              c = {
                desc = "close all but current";
                action.__raw = ''
                  function() MyBufferHelper.close_all(true) end
                '';
              };
            };
          };
          c = {
            desc = "Close current buffer";
            action.__raw = ''
              function() MyBufferHelper.close() end
            '';
          };
        };
      };
      L = {
        desc = "next buffer";
        action = "<Cmd>bnext<CR>";
      };
      H = {
        desc = "previous buffer";
        action = "<Cmd>bprev<CR>";
      };
      "<C-Left>" = {
        desc = "resize left";
        action = ":vertical resize -5<CR>";
      };
      "<C-Right>" = {
        desc = "resize right";
        action = ":vertical resize +5<CR>";
      };
    };
    v = {
      "<Tab>" = {
        desc = "indent";
        action = ">gv";
      };
      "<S-Tab>" = {
        desc = "unindent";
        action = "<gv";
      };
    };
  };
  unpackCollection = object: lib.attrsets.mapAttrsToList
    (key: value: value // {
      inherit key;
    })
    object;
  carryPrefixes = prefixes: object: object // (
    lib.attrsets.zipAttrsWithNames
      [ "mode" "desc" "key" ]
      (key: vs: lib.strings.concatStringsSep
        (if key == "key" then "" else " ")
        (lib.lists.remove "" vs)
      )
      [ prefixes object ]
  );

  getFinal = prefixes: object:
    let
      merged = carryPrefixes prefixes object;
    in
    (
      if lib.attrsets.hasAttrByPath [ "children" ] merged
      then (map (child: getFinal merged child) (unpackCollection merged.children))
      else [ ]
    ) ++ [ merged ];

  normalized =
    lib.lists.flatten
      (lib.attrsets.mapAttrsToList
        (mode: value: map
          (x: x // { inherit mode; })
          (unpackCollection value))
        keymaptree
      );
in
{
  keymap = builtins.listToAttrs
    (builtins.filter
      (attr: attr.value != "")
      (map
        (attr: {
          name = attr.key;
          value = {
            desc = attr.desc;
            mode = attr.mode;
            cond = attr.cond or null;
            action = attr.action or null;
          };
        })
        (lib.lists.flatten (
          map (getFinal { }) normalized
        ))
      )
    );
}

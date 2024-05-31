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
                lua = true;
                action = ''
                  function() vim.lsp.buf.code_action() end
                '';
                cond = "testDocument/codeAction";
              };
              r = {
                desc = "rename";
                lua = true;
                action = ''
                  function() vim.lsp.buf.rename() end
                '';
                cond = "testDocument/rename";
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
          };
          b = {
            desc = "Buffers";
            children = {
              c = {
                desc = "close all but current";
                lua = true;
                action = ''
                  function() MyBufferHelper.close_all(true) end
                '';
              };
            };
          };
          c = {
            desc = "Close current buffer";
            lua = true;
            action = ''
              function() MyBufferHelper.close() end
            '';
          };
        };
      };
      L = {
        desc = "next buffer";
        action = "<Cmd>bnest<CR>";
      };
      H = {
        desc = "previous buffer";
        action = "<Cmd>bprev<CR>";
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
  getFinalMap = prefixes: object:
    let
      merged = carryPrefixes prefixes object;
    in
    if lib.attrsets.hasAttrByPath [ "children" ] merged
    then map (child: getFinalMap merged child) (unpackCollection merged.children)
    else [ merged ];

  getFinalGroups = prefixes: object:
    let
      merged = carryPrefixes prefixes object;
    in
    if lib.attrsets.hasAttrByPath [ "children" ] merged
    then (map (child: getFinalGroups merged child) (unpackCollection merged.children)) ++ [ merged ]
    else [ ];

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
  keymaps = map
    (attr: {
      mode = attr.mode;
      key = attr.key;
      lua = attr.lua or false;
      action = attr.action;
      options = {
        desc = attr.desc;
      };
    })
    (lib.lists.flatten (
      map (getFinalMap { }) normalized
    ));
  keymapGroups = builtins.listToAttrs
    (builtins.filter
      (attr: attr.value != "")
      (map
        (attr: {
          name = attr.key;
          value = attr.desc;
        })
        (lib.lists.flatten (
          map (getFinalGroups { }) normalized
        ))
      )
    );
}

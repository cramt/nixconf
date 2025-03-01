{
  pkgs,
  inputs,
  lib,
  ...
}: let
  yazi = inputs.yazi.packages.${pkgs.system}.default;
  pluginNames = [
    "yazi-rs/plugins:mount"
    # this one is a fork https://github.com/dawsers/fuse-archive.yazi/pull/7
    "kirasok/fuse-archive"
    "Reledia/glow"
  ];
in {
  config = {
    # this is a hacky solution, but the best one i found
    home.activation = {
      linkHomeLedger = lib.hm.dag.entryAfter ["writeBoundary"] ''

        ${lib.concatStrings (builtins.map (name: "PATH=PATH:${pkgs.git}/bin ${yazi}/bin/ya pack -a ${name} || true\n") pluginNames)}
        PATH=PATH:${pkgs.git}/bin ${yazi}/bin/ya pack -u || true
      '';
    };
    home.packages = [
      pkgs.fuse-archive
      pkgs.glow
      pkgs.ueberzugpp
      pkgs.chafa
    ];
    programs.yazi = {
      enable = true;
      enableZshIntegration = true;
      initLua = ./init.lua;
      package = yazi;
      shellWrapperName = "y";

      keymap = {
        manager = {
          prepend_keymap = [
            {
              on = "M";
              run = "plugin mount";
            }
            {
              on = "<Right>";
              run = "plugin fuse-archive mount";
              desc = "Enter or Mount selected archive";
            }
            {
              on = "<Left>";
              run = "plugin fuse-archive unmount";
              desc = "Leave or Unmount selected archive";
            }
          ];
        };
      };

      settings = {
        manager = {
          show_hidden = true;
        };
        plugin = {
          prepend_previewers = [
            {
              name = "*.md";
              run = "glow";
            }
          ];
        };
      };
    };
  };
}

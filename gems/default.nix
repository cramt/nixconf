{ pkgs }: builtins.listToAttrs (builtins.map
  (x: {
    name = x;
    value = pkgs.bundlerApp {
      pname = x;
      gemdir = ./.;
      exes = [ x ];
    };
  }) [ "ruby-lsp" "rubocop" ])

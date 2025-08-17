{pkgs}: let
  gemsetFull = builtins.fromJSON (builtins.readFile (pkgs.runCommand "gemset-generate" {buildInputs = [pkgs.ruby];} ''
    cd ${./.}
    ruby ${./gemset_generator.rb} > $out
  ''));
  gemset = gemsetFull.${pkgs.system} // gemsetFull.ruby;
in
  builtins.listToAttrs (builtins.map
    (x: {
      name = x;
      value = pkgs.bundlerApp {
        pname = x;
        gemdir = ./.;
        gemset = gemset;
        exes = [x];
      };
    }) ["ruby-lsp" "rubocop"])

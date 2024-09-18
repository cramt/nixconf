{ pkgs, config, inputs, ... }: {
  home.packages = with inputs.nixpkgs-ruby-downgrade.legacyPackages.${pkgs.system}; [
    ruby
    bundix
    ((import ../../../gems/default.nix) {
      pkgs = inputs.nixpkgs-ruby-downgrade.legacyPackages.${pkgs.system};
    }).ruby-lsp
  ];
  home. file."${ config. home. homeDirectory}/.bundle/config" = {
    text = ''
      ---
      BUNDLE_BUILD__PG: "--with-pg-config=${pkgs.postgresql.dev}/bin/pg_config"
      BUNDLE_BUILD__PSYCH: "--with-libyaml-include=${pkgs.libyaml.dev}/include --with-libyaml-lib=${pkgs.libyaml}/lib"
    '';
    enable = true;
  };
}

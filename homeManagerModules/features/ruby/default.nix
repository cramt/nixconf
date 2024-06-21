{ pkgs, config, inputs, ... }: {
  home.packages = with inputs.nixpkgs-ruby-downgrade.legacyPackages.${pkgs.system}; [
    ruby
    rubyPackages.ruby-lsp
  ];
  home.file."${config.home.homeDirectory}/.bundle/config" = {
    text = ''
      ---
      BUNDLE_BUILD__PG: "--with-pg-config=${pkgs.postgresql.out}/bin/pg_config"
      BUNDLE_BUILD__PSYCH: "--with-libyaml-include=${pkgs.libyaml.dev}/include --with-libyaml-lib=${pkgs.libyaml}/lib"
    '';
    enable = true;
  };
}

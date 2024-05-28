{ pkgs, config, inputs, ... }: {
  home.packages = with inputs.nixpkgs-stable.legacyPackages.${pkgs.system}; [
    ruby
    rubyPackages.yard
  ];
  home.file."${config.home.homeDirectory}/.bundle/config" = {
    text = ''
      ---
      BUNDLE_BUILD__PG: "--with-pg-config=${pkgs.postgresql.out}/bin/pg_config"
    '';
    enable = true;
  };
}

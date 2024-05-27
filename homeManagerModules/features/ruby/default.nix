{ pkgs, config, inputs, ... }: {
  home.packages = [
    inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.ruby
  ];
  home.file."${config.home.homeDirectory}/.bundle/config" = {
    text = ''
      ---
      BUNDLE_BUILD__PG: "--with-pg-config=${pkgs.postgresql.out}/bin/pg_config"
    '';
    enable = true;
  };
}

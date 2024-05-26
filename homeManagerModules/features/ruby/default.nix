{ pkgs, config, inputs, ... }: {
  home.packages = [
    inputs.nixpkgs-stable.legacyPackages.${pkgs.system}.ruby
  ];
  home.sessionPath = [
    "/home/cramt/.local/share/gem/ruby/3.1.0/bin"
  ];
  home.file."${config.home.homeDirectory}/.bundle/config" = {
    text = ''
      ---
      BUNDLE_BUILD__PG: "--with-pg-config=${pkgs.postgresql.out}/bin/pg_config"
    '';
    enable = true;
  };
}

{ pkgs, inputs, ... }: {
  home.packages = with pkgs; [
    cockatrice
  ];

  xdg.dataFile."Cockatrice/Cockatrice/themes/DarkMingo" = {
    enable = true;
    source = inputs.darkmingo-cockactrice-theme;
    recursive = true;
  };
}

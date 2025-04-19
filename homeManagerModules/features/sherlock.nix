{inputs, ...}: {
  imports = [
    inputs.sherlock.homeManagerModules.default
  ];

  programs.sherlock = {
    enable = true;
    settings = {
      aliases = {
        vesktop = {
          name = "Discord";
        };
      };
      launchers = [
        {
          name = "App";
          type = "app_launcher";
          args = {};
          priority = 10;
          home = true;
        }
        {
          name = "Web Search";
          type = "web_launcher";
          alias = "gg";
          args = {
            search_engine = "google";
            icon = "google";
          };
          priority = 0;
        }
        {
          name = "Calculator";
          type = "calculation";
          alias = "cc";
          args = {
            capabilities = [
              "calc.math"
              "calc.units"
            ];
          };
          priority = 1;
        }
      ];
    };
  };
}

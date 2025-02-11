{
  pkgs,
  inputs,
  ...
}: {
  config = {
    home.packages = with pkgs; [
      alacritty
      kitty
      brightnessctl
      pavucontrol
      adwaita-qt
      gimp
      inputs.zen-browser.packages."${pkgs.system}".default
    ];
    xdg = {
      mimeApps = {
        enable = true;
        defaultApplications = let
          mimeTypes = [
            "application/x-extension-htm"
            "application/x-extension-html"
            "application/x-extension-shtml"
            "application/x-extension-xht"
            "application/x-extension-xhtml"
            "application/xhtml+xml"
            "image/svg+xml"
            "image/jpeg"
            "image/png"
            "text/html"
            "text/uri-list"
            "x-scheme-handler/chrome"
            "x-scheme-handler/http"
            "x-scheme-handler/https"
          ];
        in
          builtins.listToAttrs (builtins.map (v: {
              name = v;
              value = "zen.desktop";
            })
            mimeTypes);
      };
    };
  };
}

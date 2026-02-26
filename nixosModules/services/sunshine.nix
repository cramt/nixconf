{
  pkgs,
  inputs,
  ...
}: let
  # TODO: remove once sunshine builds on unstable
  pkgs-stable = inputs.nixpkgs-stable.legacyPackages.${pkgs.system};
in {
  services.sunshine = {
    enable = true;
    autoStart = true;
    capSysAdmin = true;
    openFirewall = true;
    package = pkgs-stable.sunshine;
  };
}

# Library, queue and history counts per *arr, for luna's metrics. Wired by hand
# rather than through nixarr.exporters, which binds 0.0.0.0, opens the firewall
# for it, and skips bazarr. Not a toggle of its own: it follows nixarr and the
# metrics exporter both being on.
{...}: {
  flake.nixosModules."services.nixarr-metrics" = {
    config,
    lib,
    ...
  }: let
    # The *arr apps exportarr scrapes, by their nixarr name.
    arrPorts = {
      sonarr = 8989;
      radarr = 7878;
      prowlarr = 9696;
      bazarr = 6767;
    };
    portName = name: "exportarr_${name}";
    port = name: config.port-selector.ports.${portName name};
    forEachArr = f: lib.mapAttrs' f arrPorts;
  in {
    config = lib.mkIf (config.myNixOS.services.nixarr.enable && config.myNixOS.services.metrics.exporter.enable) {
      port-selector.auto-assign = map portName (lib.attrNames arrPorts);

      services.prometheus.exporters = forEachArr (name: appPort:
        lib.nameValuePair "exportarr-${name}" {
          enable = true;
          url = "http://127.0.0.1:${toString appPort}";
          apiKeyFile = "${config.nixarr.stateDir}/secrets/${name}.api-key";
          listenAddress = "127.0.0.1";
          port = port name;
        });

      # nixarr's <name>-api units are what write the key file.
      systemd.services = forEachArr (name: _:
        lib.nameValuePair "prometheus-exportarr-${name}-exporter" {
          after = ["${name}-api.service"];
          requires = ["${name}-api.service"];
        });

      myNixOS.services.metrics.localJobs =
        forEachArr (name: _:
          lib.nameValuePair "exportarr-${name}" {port = port name;});
    };
  };
}

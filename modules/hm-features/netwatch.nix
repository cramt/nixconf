{ ... }: {
  hmModules.features.netwatch = { config, lib, pkgs, ... }: {
    options.myHomeManager.netwatch = {
      enable = lib.mkEnableOption "myHomeManager.netwatch";
      target = lib.mkOption {
        type = lib.types.str;
        default = "1.1.1.1";
        description = "Off-net host to probe with ICMP. Kept for comparison only: this ISP "
                    + "deprioritises ICMP heavily, so treat its loss figures as unreliable.";
      };
      tcpHost = lib.mkOption {
        type = lib.types.str;
        default = "cloudflare.com";
        description = "Host to time TCP handshakes against. This is the trustworthy signal, "
                    + "since a handshake rides the same queues as real traffic.";
      };
      interval = lib.mkOption {
        type = lib.types.int;
        default = 20;
        description = "Seconds to sleep between samples.";
      };
    };
    config = lib.mkIf config.myHomeManager.netwatch.enable {
      systemd.user.services.netwatch = let
        cfg = config.myHomeManager.netwatch;
        binary = pkgs.writeShellApplication {
          name = "netwatch";
          runtimeInputs = with pkgs; [ iputils curl iproute2 gawk gnugrep coreutils ];
          text = builtins.readFile ./netwatch.sh;
        };
      in {
        Service = {
          ExecStart = "${binary}/bin/netwatch";
          Environment = [
            "NETWATCH_TARGET=${cfg.target}"
            "NETWATCH_TCP_HOST=${cfg.tcpHost}"
            "NETWATCH_INTERVAL=${toString cfg.interval}"
          ];
          Restart = "always";
          RestartSec = "10s";
          Nice = 10;
        };
        Unit = { Description = "Network health sampler (catches intermittent WAN loss)"; };
        Install = { WantedBy = ["network-online.target"]; };
      };
    };
  };
}

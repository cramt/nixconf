{config, ...}: let
in {
  config = {
    boot.kernel.sysctl = {
      "net.ipv4.conf.all.forwarding" = true;
      "net.ipv6.conf.all.forwarding" = true;

      "net.ipv6.conf.all.accept_ra" = 0;
      "net.ipv6.conf.all.autoconf" = 0;
      "net.ipv6.conf.all.use_tempaddr" = 0;

      "net.ipv6.conf.wan0.accept_ra" = 2;
      "net.ipv6.conf.wan0.autoconf" = 1;
      "net.ipv6.conf.wan1.accept_ra" = 2;
      "net.ipv6.conf.wan1.autoconf" = 1;
    };
    networking = {
      nat.enable = false;
      firewall.enable = false;
      useDHCP = false;
      nameservers = ["8.8.8.8"];
      nftables = {
        enable = true;
        ruleset = ''
          table inet filter {
            chain output {
              type filter hook output priority 100; policy accept;
            }

            chain input {
              type filter hook input priority filter; policy drop;

              # Allow trusted networks to access the router
              iifname {
                "lan",
              } counter accept

              # Allow returning traffic from ppp0 and drop everthing else
              iifname "ppp0" ct state { established, related } counter accept
              iifname "ppp0" drop
            }

            chain forward {
              type filter hook forward priority filter; policy drop;

              # Allow trusted network WAN access
              iifname {
                      "lan",
              } oifname {
                      "ppp0",
              } counter accept comment "Allow trusted LAN to WAN"

              # Allow established WAN to return
              iifname {
                      "ppp0",
              } oifname {
                      "lan",
              } ct state established,related counter accept comment "Allow established back to LANs"
            }
          }

          table ip nat {
            chain prerouting {
              type nat hook prerouting priority filter; policy accept;
            }

            # Setup NAT masquerading on the ppp0 interface
            chain postrouting {
              type nat hook postrouting priority filter; policy accept;
              oifname "ppp0" masquerade
            }
          }
        '';
      };
      vlans = {
        wan = {
          id = 10;
          interface = "enp1s0";
        };
        lan = {
          id = 20;
          interface = "enp2s0";
        };
        iot = {
          id = 90;
          interface = "enp2s0";
        };
      };
      interfaces = {
        enp1s0.useDHCP = false;
        enp2s0.useDHCP = false;
        enp3s0.useDHCP = false;

        wan.useDHCP = false;
        lan = {
          ipv4.addresses = [
            {
              address = "10.1.1.1";
              prefixLength = 24;
            }
          ];
        };
        iot = {
          ipv4.addresses = [
            {
              address = "10.1.90.1";
              prefixLength = 24;
            }
          ];
        };
      };
    };
    services.avahi = {
      enable = true;
      reflector = true;
      allowInterfaces = [
        "lan"
        "iot"
      ];
    };
    services.pppd = {
      enable = true;
      peers = {
        edpnet = {
          # Autostart the PPPoE session on boot
          autostart = true;
          enable = true;
          config = ''
            plugin rp-pppoe.so wan

            persist
            maxfail 0
            holdoff 5

            noipdefault
            defaultroute
          '';
        };
      };
    };
  };
}

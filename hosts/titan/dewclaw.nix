# Dewclaw configuration for the Archer C5 v2 (titan).
# Dewclaw pushes UCI config to a *running* OpenWrt router over SSH; it does
# NOT flash firmware. Flash titan with `nix build .#titan-img` first, then
# run `just deploy_titan` to apply this config over the network.
#
# TODO(alex): change `deploy.host` once titan has a permanent LAN address.
# Default `192.168.1.1` is the fresh-flash OpenWrt address — fine for the
# first deploy when titan is on a crossover/isolated LAN.
{
  openwrt.titan = {
    deploy.host = "192.168.1.1";
    deploy.user = "root";
    deploy.sshConfig = {
      # OpenWrt 19.07 dropbear ships old key exchange algorithms only.
      KexAlgorithms = "+diffie-hellman-group14-sha1";
      HostKeyAlgorithms = "+ssh-rsa";
      PubkeyAcceptedAlgorithms = "+ssh-rsa";
      # Trust on first use — there's no record of titan's host key yet.
      StrictHostKeyChecking = "accept-new";
      UserKnownHostsFile = "~/.ssh/known_hosts";
    };

    etc."dropbear/authorized_keys".text = ''
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIwaPHqAJyayzLGfkEhwoDskUUyTr0aEovcc1Nzg2zXH alex.cramt@gmail.com
      ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIWPMez5MadLlJ+NbdUJBDpd3MWCYI28gvA4Ddi5wD8I alex.cramt@gmail.com
    '';

    # Preserve defaults for these — the image-builder bakes in working values
    # and re-emitting them from here would risk breaking first-boot reachability.
    uci.retain = [
      "ucitrack"
      "firewall"
      "luci"
      "rpcd"
      "network"
      "wireless"
      "dhcp"
    ];

    uci.settings = {
      system = {
        system = [
          {
            hostname = "titan";
            timezone = "UTC";
          }
        ];
      };

      dropbear.dropbear = [
        {
          # Key-only auth. The authorized_keys file above is the only way in.
          PasswordAuth = "off";
          RootPasswordAuth = "off";
          Port = 22;
        }
      ];
    };
  };
}

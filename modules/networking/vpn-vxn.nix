# vxn.rs commercial WireGuard endpoint — full tunnel (0.0.0.0/0, ::/0).
#
# Off at boot by default: this is a "flip it on when I want it" VPN, not
# infrastructure. Start/stop it with
#   systemctl start wg-quick-vxn   /   systemctl stop wg-quick-vxn
# or set `autostart = true` on a host that should always be tunnelled.
{ ... }: {
  flake.nixosModules."networking.vpn-vxn" = { config, lib, ... }:
  let
    cfg = config.myNixOS.vpn.vxn;
    secrets = config.services.onepassword-secrets.secretPaths;
  in {
    options.myNixOS.vpn.vxn = {
      enable = lib.mkEnableOption "myNixOS.vpn.vxn";
      autostart = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Bring the tunnel up at boot instead of on demand.";
      };
    };

    config = lib.mkIf cfg.enable {
      # wg-quick rather than networking.wireguard.interfaces: a 0.0.0.0/0
      # AllowedIPs needs the fwmark + `suppress_prefixlength 0` rule dance to
      # capture the default route without eating LAN routes, and DNS= needs a
      # resolvconf hook. wg-quick does both; the raw netlink module does neither.
      networking.wg-quick.interfaces.vxn = {
        address = [ "10.10.98.4/32" "2a05:6e02:1088:1c17::4/128" ];
        dns = [ "10.10.98.1" ];
        privateKeyFile = secrets.vxnPrivateKey;
        autostart = cfg.autostart;
        peers = [
          {
            publicKey = "A1HQljKzWdrUJk6SibrMLbGHsU0eWKhNhXZAGhrWKgE=";
            presharedKeyFile = secrets.vxnPresharedKey;
            allowedIPs = [ "0.0.0.0/0" "::/0" ];
            endpoint = "wg.vxn.rs:51820";
            persistentKeepalive = 25;
          }
        ];
      };
    };
  };
}

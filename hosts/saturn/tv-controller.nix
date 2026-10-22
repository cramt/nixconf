# The living-room TV's Steam Controller, attached here over USB/IP while a
# stream runs. The TV's moonlight-tv can't forward it: the new controller's
# puck (28de:1304) is only a mouse and keyboard to its SDL. Attached here,
# Steam sees the real controller, Steam Input and all, as if the puck were
# plugged into saturn.
#
# The TV side is hand-set on the rooted TV, outside nix:
# - /var/lib/webosbrew/init.d/usbipd starts usbipd at every boot;
# - /home/root/steam-puck hands the puck to usbip-host (`bind`, printing its
#   busid) and back (`unbind`);
# - saturn's host key is in root's authorized_keys, limited to that command.
#
# While attached, the controller doesn't drive the TV's own menus.
{
  config,
  lib,
  pkgs,
  ...
}: let
  tv = "192.168.178.36";
  usbip = config.boot.kernelPackages.usbip;
  unit = "tv-steam-controller";
  puck = verb: "ssh -i /etc/ssh/ssh_host_ed25519_key -o BatchMode=yes -o ConnectTimeout=5 root@${tv} ${verb}";

  attach = pkgs.writeShellApplication {
    name = "${unit}-attach";
    runtimeInputs = [usbip pkgs.openssh];
    text = ''
      busid=$(${puck "bind"})
      # A failed attach would otherwise leave the puck bound, dead on the TV
      # too, until the next stream's stop.
      usbip attach -r ${tv} -b "$busid" || { ${puck "unbind"}; exit 1; }
    '';
  };

  detach = pkgs.writeShellApplication {
    name = "${unit}-detach";
    runtimeInputs = [usbip pkgs.openssh pkgs.gawk];
    text = ''
      # `usbip port` lists each attached device as a "Port NN:" line, with
      # the remote it came from a few lines below.
      usbip port 2>/dev/null |
        awk '/^Port/ { port = $2 + 0 } /usbip:\/\/${lib.escapeRegex tv}:/ { print port }' |
        while read -r port; do usbip detach -p "$port"; done
      ${puck "unbind"}
    '';
  };
in {
  boot.kernelModules = ["vhci-hcd"];

  programs.ssh.knownHosts.living-room-tv = {
    hostNames = [tv];
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMLQpy43bJ4MCKXWr3DSLoCdXZRCMDeSll00DQNWqup4";
  };

  systemd.services.${unit} = {
    description = "The living-room TV's Steam Controller, attached over USB/IP";
    wants = ["network-online.target"];
    after = ["network-online.target"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe attach;
      ExecStop = lib.getExe detach;
    };
  };

  # Sunshine runs as the user, and attaching takes root.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "${unit}.service" &&
          subject.user == "${config.myNixOS.sunshine.user}" &&
          ["start", "stop"].indexOf(action.lookup("verb")) >= 0) {
        return polkit.Result.YES;
      }
    });
  '';

  # --no-block: with the TV off, a stream must still start (and stop) at
  # once; the unit just fails. Every stream grabs it, ganymede's too, which
  # only matters if someone's on the TV at the same time.
  myNixOS.sunshine.prepCommands = lib.mkAfter [
    {
      do = "${pkgs.systemd}/bin/systemctl start --no-block ${unit}.service";
      undo = "${pkgs.systemd}/bin/systemctl stop --no-block ${unit}.service";
    }
  ];
}

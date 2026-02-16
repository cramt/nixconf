{
  lib,
  config,
  ...
}: let
  cfg = config.port-selector;

  # Convert a hex character to its integer value
  hexCharToInt = c:
    let
      chars = {
        "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4;
        "5" = 5; "6" = 6; "7" = 7; "8" = 8; "9" = 9;
        "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;
      };
    in chars.${c};

  # Convert first n hex chars of a string to an integer
  hexToInt = n: s:
    builtins.foldl' (acc: c: acc * 16 + hexCharToInt c) 0
      (lib.take n (lib.stringToCharacters s));

  # Hash a service name to a port in range [minPort, maxPort]
  minPort = 1025;
  maxPort = 65535;
  portRange = maxPort - minPort + 1;

  hashToPort = name:
    let
      hash = builtins.hashString "sha256" name;
      # Use 8 hex chars (32 bits) — plenty of entropy for port selection
      n = hexToInt 8 hash;
    in minPort + (lib.trivial.mod n portRange);

  # Assign ports to a list of names, avoiding collisions with usedPorts
  assignPorts = names: usedPorts:
    let
      findFree = candidate: used:
        if builtins.elem candidate used
        then findFree (if candidate >= maxPort then minPort else candidate + 1) used
        else candidate;
      go = remaining: used: acc:
        if remaining == [] then acc
        else let
          name = builtins.head remaining;
          rest = builtins.tail remaining;
          candidate = hashToPort name;
          port = findFree candidate used;
        in go rest (used ++ [port]) (acc // { ${name} = port; });
    in go names usedPorts {};

  # Pinned ports: flip from { "portNum" = "name"; } to { "name" = portNum; }
  pinnedPorts = lib.mapAttrs' (port: name: {
    name = name;
    value = lib.toInt port;
  }) cfg.set-ports;

  pinnedPortValues = lib.attrValues pinnedPorts;

  # Blocked port ranges flattened to a list
  blockedPorts = builtins.concatMap
    ({ from, to }: lib.range from to)
    cfg.additional-blocked-port-ranges;

  autoAssigned = assignPorts cfg.auto-assign (pinnedPortValues ++ blockedPorts);

  allPorts = pinnedPorts // autoAssigned;
in {
  options.port-selector = {
    set-ports = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      description = "Manually pinned port assignments (port number string -> service name)";
    };
    auto-assign = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Service names to auto-assign ports to";
    };
    additional-blocked-port-ranges = lib.mkOption {
      default = [];
      type = lib.types.listOf (lib.types.submodule {
        options = {
          from = lib.mkOption {
            type = lib.types.ints.u16;
          };
          to = lib.mkOption {
            type = lib.types.ints.u16;
          };
        };
      });
    };
    ports = lib.mkOption {
      type = lib.types.attrsOf lib.types.ints.u16;
      readOnly = true;
      default = allPorts;
      description = "Final resolved port map (service-name -> port)";
    };
  };
  config.port-selector = {
    additional-blocked-port-ranges = [
      { from = 0; to = 1024; }
    ];
  };
}

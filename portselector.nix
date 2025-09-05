{
  pkgs,
  lib,
  config,
  ...
}: let
  input = {
    setPorts = lib.attrsets.filterAttrs (n: v: v != null) config.port-selector.set-ports;
    autoAssign = config.port-selector.auto-assign;
    additionalBlockedPortRanges = config.port-selector.additional-blocked-port-ranges;
  };
  gen = pkgs.writers.writeJS "gen-ports" {} ''
    const { createHash } = require("node:crypto")
    const fs = require('node:fs');
    const rawHash = (val) => {
      const h = createHash("sha256")
      h.update(val)
      return parseInt(h.digest("hex"), 16)
    }
    const inputRaw = process.env.INPUT
    const seed = rawHash(inputRaw)
    const hash = (val) => {
      const h = createHash("sha256")
      h.update(seed.toString(16))
      h.update(val.toString())
      return parseInt(h.digest("hex"), 16)
    }
    const inclusiveRange = function* (start, end) {
        for(let i = start; i <= end; i++) {
           yield i
        }
    }
    const assertNoDuplicates = (arr) => {
        const uniqueElements = new Set()
        const duplicates = [];

        arr.forEach(item => {
          if (uniqueElements.has(item)) {
            duplicates.push(item);
          } else {
            uniqueElements.add(item);
          }
        });

        if(duplicates.length !== 0) {
            throw "duplicates found " + JSON.strinify(duplicates)
        }
    }
    const { setPorts, autoAssign, additionalBlockedPortRanges } = JSON.parse(inputRaw)
    assertNoDuplicates([...Object.values(setPorts), autoAssign])
    autoAssign.sort((a, b) => hash(a) - hash(b))
    const blockedPortSet = new Set([
        ...additionalBlockedPortRanges.map(({from, to}) => [...inclusiveRange(from, to)]).flat(),
        ...Object.keys(setPorts).map(x => parseInt(x))
    ])
    const freePorts = Array.from(new Set([...inclusiveRange(0, 2**16)]).difference(blockedPortSet))
    freePorts.sort((a, b) => hash(a) - hash(b))
    autoAssign.forEach(x => {
        const port = freePorts.shift().toString()
        setPorts[port] = x
    })
    const output = Object.fromEntries(Object.entries(setPorts).map(([a, b]) => [b, parseInt(a)]))
    fs.writeFileSync(process.env.out, JSON.stringify(output))
  '';
  output = pkgs.runCommand "ports" {} ''
    INPUT='${builtins.toJSON input}' ${gen}
  '';
in {
  options = {
    port-selector = lib.mkOption {
      type = lib.types.submodule {
        options = {
          set-ports = lib.mkOption {
            default = {};
            type = lib.types.submodule {
              options = builtins.listToAttrs (builtins.map (i: {
                name = builtins.toString i;
                value = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                };
              }) (lib.lists.range 0 65536));
            };
          };
          auto-assign = lib.mkOption {
            default = [];
            type = lib.types.listOf lib.types.str;
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
            type = lib.types.attrsOf (lib.types.ints.u16);
          };
        };
      };
    };
  };
  config.port-selector = {
    additional-blocked-port-ranges = [
      {
        from = 0;
        to = 1024;
      }
    ];
    ports = builtins.fromJSON (builtins.readFile output);
  };
}

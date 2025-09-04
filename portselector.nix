{
  pkgs,
  lib,
  config,
  ...
}: let
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
    const input = JSON.parse(inputRaw)
    const donePart = Object.fromEntries(Object.entries(input).filter(([_, v]) => !!v.port))
    const notDonePart = Object.fromEntries(Object.entries(input).filter(([_, v]) => !v.port))
    const portsTaken = new Set(Object.values(donePart).map(x => x.port))
    const possiblePorts = Array.from(Array((2**16) + 1).keys()).filter(x => x > 1024 || !portsTaken.has(x))
    possiblePorts.sort((a, b) => hash(a) - hash(b))
    const toAssign = Object.keys(notDonePart)
    toAssign.sort((a, b) => hash(a) - hash(b))
    toAssign.forEach(x => {
      const port = possiblePorts.shift()
      notDonePart[x].port = port
    })
    const output = Object.assign(donePart, notDonePart)
    fs.writeFileSync(process.env.out, JSON.stringify(output))
  '';
  output = pkgs.runCommand "ports" {} ''
    INPUT='${builtins.toJSON config.port-selector.services}' ${gen}
  '';
in {
  options = {
    port-selector = lib.mkOption {
      type = lib.types.submodule {
        options = {
          services = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                port = lib.mkOption {
                  type = lib.types.nullOr lib.types.ints.u16;
                  default = null;
                };
              };
            });
            default = {};
          };
          ports = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
              options = {
                port = lib.mkOption {
                  type = lib.types.ints.u16;
                };
              };
            });
          };
        };
      };
    };
  };
  config.port-selector.ports = builtins.fromJSON (builtins.readFile output);
}

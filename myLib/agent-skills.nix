# Skill libraries and helper binaries shared by every coding agent on this
# machine — Claude Code, opencode, pi and omp (all under
# modules/hm-features/). They all consume the same SKILL.md dirs, so the
# enumeration and the exclusion list live here rather than being copied into
# each module and drifting. Only the plumbing differs: ~/.claude/skills
# symlinks, opencode's `skills` attrset, pi's repeated `--skill`, and omp's
# skills.customDirectories.
#
# It lives in myLib/ rather than modules/ because import-tree turns every .nix
# file under modules/ into a flake-parts module; this is a plain helper,
# imported by relative path the same way myLib/site.nix is.
{
  lib,
  pkgs,
  inputs,
}: let
  dirsIn = path:
    builtins.attrNames
    (lib.filterAttrs (_: type: type == "directory") (builtins.readDir path));

  skillsRoot = ../modules/hm-features/claude-skills;

  # Vendored rather than pinned: upstream pstack is one tree rooted at
  # `poteto-mode`, and only these ten stand alone. Each also needs its
  # `disable-model-invocation` flag stripped to fire without that dispatcher,
  # so there's nothing for a pin to track cleanly. See pstack/README.md.
  pstackDir = "${skillsRoot}/pstack";

  # mattpocock/skills nests a category level (skills/<category>/<name>), so
  # flatten two deep. Enumerating rather than listing means new upstream skills
  # arrive on `just update`; the exclusion is the only thing to maintain.
  # setup-matt-pocock-skills rewrites a repo's issue-tracker and label
  # vocabulary to match upstream's conventions, which ours don't follow.
  mattpocockExclude = ["setup-matt-pocock-skills"];
  mattpocockRoot = "${inputs.mattpocock-skills}/skills";
in {
  # Each entry is { name; path; } where path is a store path to a skill
  # directory containing SKILL.md — the shape both agents' config wants.
  pstack =
    map (name: {
      inherit name;
      path = "${pstackDir}/${name}";
    })
    (dirsIn pstackDir);

  mattpocock =
    lib.filter (s: !(builtins.elem s.name mattpocockExclude))
    (lib.concatMap
      (category:
        map (name: {
          inherit name;
          path = "${mattpocockRoot}/${category}/${name}";
        })
        (dirsIn "${mattpocockRoot}/${category}"))
      (dirsIn mattpocockRoot));

  status = {
    name = "status";
    path = "${skillsRoot}/status";
  };

  mtg-commander = {
    name = "mtg-commander";
    path = "${skillsRoot}/mtg-commander/SKILL.md";
  };

  # The mtg-commander skill leans on this helper for every card lookup, so it
  # gets a real derivation with its deps closed over rather than a bare script
  # in the skill dir: an agent that can't find `jq` would silently fall back to
  # guessing card data from memory, which is the one thing the skill forbids.
  #
  # openssl is new, for `play`: it supplies the AES-CTR keystream behind
  # reproducible seeded deals. coreutils was already load-bearing (stat, date,
  # mktemp, mv) but resolving off the ambient PATH, because
  # writeShellApplication prepends runtimeInputs rather than replacing PATH;
  # `play` adds `shuf` to that list, and a silently missing shuffler is the
  # worst failure this script could have.
  # progress-engine owns decklist parsing outright. `check` and `play` used to
  # share one jq regex on the strength of a comment begging future editors not
  # to copy it; now they shell out to the same binary instead, which is the only
  # version of that guarantee a comment cannot undermine.
  scryfall = pkgs.writeShellApplication {
    name = "scryfall";
    runtimeInputs =
      (with pkgs; [curl jq gzip util-linux coreutils openssl])
      ++ [inputs.progress-engine.packages.${pkgs.system}.default];
    text = builtins.readFile "${skillsRoot}/mtg-commander/scryfall.sh";
  };

  agent-browser = pkgs.callPackage ../packages/agent-browser {};
}

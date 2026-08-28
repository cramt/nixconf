# Prism Launcher, with a default heap that can actually run a modpack.
#
# Upstream's default is 4096 MiB. That is fine for vanilla and hopeless for a
# large pack: Craftoria (~525 mods) pinned old gen at 99%, spent ~40% of its
# runtime in full GC, and died with OutOfMemoryError shortly after world load.
#
# What this can and can't do declaratively: Prism owns
# ~/.local/share/PrismLauncher/prismlauncher.cfg and rewrites the entire file
# when it exits, so it cannot be a home.file symlink without breaking every
# setting the launcher tries to save. The values here are therefore re-asserted
# on each activation, and a change made in Prism's own settings GUI wins until
# the next switch. Per-instance overrides (OverrideMemory=true in an instance's
# instance.cfg) also still win; this only moves the global default.
{...}: {
  hmModules.features.prismlauncher = {
    config,
    lib,
    pkgs,
    ...
  }: let
    cfg = config.myHomeManager.prismlauncher;

    # The file is Qt QSettings INI with [General] and [UI] sections, so the keys
    # have to be set inside [General] rather than appended at EOF.
    apply = pkgs.writeShellScript "prismlauncher-memory" ''
      set -eu
      conf="$HOME/.local/share/PrismLauncher/prismlauncher.cfg"
      mkdir -p "$(dirname "$conf")"
      [ -e "$conf" ] || printf '[General]\n' > "$conf"

      ${pkgs.gawk}/bin/awk -v max=${toString cfg.maxMemMiB} -v min=${toString cfg.minMemMiB} '
        function flush_general() {
          if (!seen_max) print "MaxMemAlloc=" max
          if (!seen_min) print "MinMemAlloc=" min
          seen_max = 1; seen_min = 1
        }
        /^\[General\]$/ { print; in_general = 1; next }
        /^\[/ { if (in_general) flush_general(); in_general = 0; print; next }
        in_general && /^MaxMemAlloc=/ { print "MaxMemAlloc=" max; seen_max = 1; next }
        in_general && /^MinMemAlloc=/ { print "MinMemAlloc=" min; seen_min = 1; next }
        { print }
        END { if (in_general) flush_general() }
      ' "$conf" > "$conf.tmp"
      mv "$conf.tmp" "$conf"
    '';
  in {
    options.myHomeManager.prismlauncher = {
      enable = lib.mkEnableOption "myHomeManager.prismlauncher";

      maxMemMiB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 10240;
        description = ''
          Default -Xmx for new instances, in MiB. Sized for a large NeoForge
          pack with headroom; going much past this trades OOM safety for longer
          G1 pauses rather than more throughput.
        '';
      };

      minMemMiB = lib.mkOption {
        type = lib.types.ints.positive;
        default = 4096;
        description = "Default -Xms for new instances, in MiB.";
      };
    };

    config = lib.mkIf cfg.enable {
      home.packages = [pkgs.prismlauncher];

      # Same reasoning as steam-input: activation runs before any user session
      # exists, so Prism isn't up to race with over the config file.
      home.activation.prismlauncher-memory = lib.hm.dag.entryAfter ["writeBoundary"] ''
        run ${apply}
      '';
    };
  };
}

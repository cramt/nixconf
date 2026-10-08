# Installs BepInEx mods into Enter the Gungeon's Steam install from a JSON spec.
#
# Mods have to be real files inside the game directory, which Steam owns and
# rewrites on update or verify, so they're copied in on every activation rather
# than symlinked. Everything written is listed in a manifest next to the game,
# so a mod dropped from the nix config is removed next time instead of lingering.
#
# The native Linux build only loads BepInEx when launched through
# start_game_bepinex.sh, which means setting Steam's per-game launch option in
# localconfig.vdf. That file has the same constraint as shortcuts.vdf: Steam
# rewrites it from memory on exit, so it's only touched while Steam is down.
# It's edited as text rather than round-tripped through python's vdf, whose
# writer escapes ' and ? in ways Steam's parser doesn't undo.
{pkgs}:
pkgs.writers.writePython3Bin "gungeon-mods" {
  flakeIgnore = ["E501"];
} ''
  """Install declared BepInEx mods into Enter the Gungeon."""
  import glob
  import json
  import os
  import shutil
  import sys

  APPID = "311690"
  MANIFEST = ".nix-gungeon-mods"


  def steam_is_running():
      for comm in glob.glob("/proc/[0-9]*/comm"):
          try:
              with open(comm) as handle:
                  if handle.read().strip() == "steam":
                      return True
          except OSError:
              continue
      return False


  def copy_tree(src, dst, written):
      for root, _, files in os.walk(src):
          target_root = os.path.normpath(os.path.join(dst, os.path.relpath(root, src)))
          os.makedirs(target_root, exist_ok=True)
          for name in files:
              target = os.path.join(target_root, name)
              if os.path.exists(target):
                  os.chmod(target, 0o644)
              shutil.copyfile(os.path.join(root, name), target)
              # Thunderstore zips carry no exec bit, and Steam has to run the launcher.
              os.chmod(target, 0o755 if name.endswith(".sh") else 0o644)
              written.append(target)


  def remove_previous(game_dir):
      path = os.path.join(game_dir, MANIFEST)
      try:
          with open(path) as handle:
              previous = handle.read().splitlines()
      except OSError:
          return
      for file in previous:
          if os.path.isfile(file):
              os.remove(file)


  def install(spec, game_dir):
      remove_previous(game_dir)
      written = []
      copy_tree(os.path.join(spec["loader"], "BepInExPack_EtG"), game_dir, written)
      # r2modman's layout, which the packages are authored against.
      for mod in spec["mods"]:
          plugins = os.path.join(mod["src"], "plugins")
          if os.path.isdir(plugins):
              copy_tree(plugins, os.path.join(game_dir, "BepInEx", "plugins", mod["name"]), written)
          monomod = os.path.join(mod["src"], "monomod")
          if os.path.isdir(monomod):
              copy_tree(monomod, os.path.join(game_dir, "BepInEx", "monomod"), written)
      with open(os.path.join(game_dir, MANIFEST), "w") as handle:
          handle.write("\n".join(written) + "\n")


  def quote(value):
      return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


  def with_launch_options(lines, launch):
      """Set apps/<APPID>/LaunchOptions under Software/Valve/Steam, in place."""
      path = []
      pending = None
      for i, line in enumerate(lines):
          token = line.strip()
          if token == "{":
              path.append(pending)
              if path == ["UserLocalConfigStore", "Software", "Valve", "Steam", "apps", APPID]:
                  indent = "\t" * len(path)
                  entry = indent + quote("LaunchOptions") + "\t\t" + quote(launch) + "\n"
                  depth = 0
                  for j in range(i + 1, len(lines)):
                      inner = lines[j].strip()
                      if inner == "{":
                          depth += 1
                      elif inner == "}":
                          if depth == 0:
                              return lines[:j] + [entry] + lines[j:]
                          depth -= 1
                      elif depth == 0 and inner.startswith('"LaunchOptions"'):
                          return lines[:j] + [entry] + lines[j + 1:]
          elif token == "}":
              path.pop()
          elif token.startswith('"') and token.endswith('"') and token.count('"') == 2:
              pending = token[1:-1]
      return None


  def set_launch_options(launch):
      if steam_is_running():
          print("gungeon-mods: Steam is running; it would overwrite the launch "
                "option on exit. Quit Steam and run gungeon-mods.", file=sys.stderr)
          return
      for path in glob.glob(os.path.expanduser(
              "~/.local/share/Steam/userdata/*/config/localconfig.vdf")):
          with open(path, encoding="utf-8") as handle:
              lines = handle.readlines()
          updated = with_launch_options(lines, launch)
          if updated is None:
              # Steam only writes the block once the game has been launched.
              print(f"gungeon-mods: no entry for the game in {path}, launch it once first",
                    file=sys.stderr)
              continue
          if updated == lines:
              continue
          with open(path + ".tmp", "w", encoding="utf-8") as handle:
              handle.writelines(updated)
          os.replace(path + ".tmp", path)


  def main():
      if len(sys.argv) != 2:
          sys.exit("usage: gungeon-mods <spec.json>")
      with open(sys.argv[1]) as handle:
          spec = json.load(handle)

      game_dir = os.path.expanduser(spec["gameDir"])
      if not os.path.isfile(os.path.join(game_dir, "EtG.x86_64")):
          print("gungeon-mods: Enter the Gungeon isn't installed, skipping")
          return

      install(spec, game_dir)
      set_launch_options(
          '"' + os.path.join(game_dir, "start_game_bepinex.sh") + '" %command%')


  main()
''

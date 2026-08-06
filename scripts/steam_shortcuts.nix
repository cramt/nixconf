# Writes Steam's shortcuts.vdf (the non-Steam game list) from a JSON spec.
#
# shortcuts.vdf is binary VDF, and Steam rewrites it wholesale when it exits,
# so the usual trick of symlinking a store path doesn't work — Steam needs the
# file writable, and would clobber it anyway. This regenerates the file at
# activation instead, which makes the nix config the source of truth.
#
# That means nix OWNS the file: shortcuts added by hand through the Big Picture
# UI are removed on the next activation. LastPlayTime is carried over for
# entries whose appid still matches, so rebuilding doesn't reset play stats.
#
# Encoding is delegated to python3Packages.vdf rather than hand-rolled, because
# a subtly wrong byte layout here corrupts Steam's config rather than failing
# loudly.
{pkgs}:
pkgs.writers.writePython3Bin "steam-shortcuts" {
  libraries = [pkgs.python3Packages.vdf];
  flakeIgnore = ["E501"];
} ''
  """Regenerate Steam's non-Steam shortcut list from a JSON spec."""
  import glob
  import json
  import os
  import sys
  import zlib

  import vdf


  def shortcut_appid(exe, name):
      """Steam's legacy shortcut id: crc32(exe+name) with the high bit set.

      Stored as a signed int32, so fold values above 2**31-1 into negatives —
      grid art and controller layouts are keyed off this, so it has to match
      what Steam itself would compute.
      """
      crc = zlib.crc32((exe + name).encode("utf-8")) & 0xFFFFFFFF
      value = crc | 0x80000000
      return value - 0x100000000 if value > 0x7FFFFFFF else value


  def steam_is_running():
      for comm in glob.glob("/proc/[0-9]*/comm"):
          try:
              with open(comm) as handle:
                  if handle.read().strip() == "steam":
                      return True
          except OSError:
              continue
      return False


  def build_entry(spec, previous_playtime):
      # Steam stores these two quoted, including the literal quote characters.
      exe = '"' + spec["exe"] + '"'
      start_dir = '"' + spec["startDir"] + '"'
      appid = shortcut_appid(exe, spec["name"])
      return appid, {
          "appid": appid,
          "AppName": spec["name"],
          "Exe": exe,
          "StartDir": start_dir,
          "icon": spec.get("icon", ""),
          "ShortcutPath": "",
          "LaunchOptions": spec.get("launchOptions", ""),
          "IsHidden": 0,
          "AllowDesktopConfig": 1,
          "AllowOverlay": 1,
          "OpenVR": 0,
          "Devkit": 0,
          "DevkitGameID": "",
          "DevkitOverrideAppID": 0,
          "LastPlayTime": previous_playtime.get(appid, 0),
          "FlatpakAppID": "",
          "tags": {str(i): t for i, t in enumerate(spec.get("tags", []))},
      }


  def existing_playtime(path):
      """Map appid -> LastPlayTime from the current file, if it parses."""
      try:
          with open(path, "rb") as handle:
              current = vdf.binary_loads(handle.read())
      except (OSError, SyntaxError, ValueError):
          return {}
      out = {}
      for entry in current.get("shortcuts", {}).values():
          if isinstance(entry, dict) and "appid" in entry:
              out[entry["appid"]] = entry.get("LastPlayTime", 0)
      return out


  def main():
      if len(sys.argv) != 2:
          sys.exit("usage: steam-shortcuts <spec.json>")

      with open(sys.argv[1]) as handle:
          specs = json.load(handle)

      config_dirs = sorted(glob.glob(
          os.path.expanduser("~/.local/share/Steam/userdata/*/config")
      ))
      if not config_dirs:
          # The per-account userdata directory only exists once Steam has been
          # logged into at least once. Not an error — just nothing to do yet.
          print("steam-shortcuts: no Steam userdata yet, skipping "
                "(log into Steam once, then re-activate)")
          return

      if steam_is_running():
          print("steam-shortcuts: Steam is running; it would overwrite this on "
                "exit. Quit Steam and re-activate.", file=sys.stderr)
          return

      for config_dir in config_dirs:
          path = os.path.join(config_dir, "shortcuts.vdf")
          playtime = existing_playtime(path)

          shortcuts = {}
          for index, spec in enumerate(specs):
              _, entry = build_entry(spec, playtime)
              shortcuts[str(index)] = entry

          blob = vdf.binary_dumps({"shortcuts": shortcuts})

          try:
              with open(path, "rb") as handle:
                  if handle.read() == blob:
                      continue
          except OSError:
              pass

          tmp = path + ".new"
          with open(tmp, "wb") as handle:
              handle.write(blob)
          os.replace(tmp, path)
          print("steam-shortcuts: wrote " + str(len(specs)) + " shortcut(s) to " + path)


  main()
''

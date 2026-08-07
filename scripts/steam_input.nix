# Writes a Steam Input layout template from a JSON spec.
#
# Steam keeps the layout a game actually uses at
#   userdata/<id>/config/controller_configs/apps/<appid>/<opaque hash>/guest/
# where the hash component is Steam's own and isn't reproducible from outside,
# so that path can't be written declaratively. controller_base/templates/ can:
# anything dropped there shows up in the template list for every game,
# including non-Steam shortcuts. So the layout's *content* lives in nix and
# picking it per shortcut stays a one-time click, the same shape of manual step
# as the first Steam login that steam-shortcuts already needs.
#
# Steam ships its own templates in that directory and replaces it on update,
# which is why this re-asserts on every activation rather than writing once.
#
# The group topology below is a property of the controller, not of taste, so
# it's fixed here and only the bindings come from the spec. Steam silently
# drops a layout whose groups don't line up with their sources — it just never
# appears in the list — so this is the part worth not generating dynamically.
{pkgs}:
pkgs.writers.writePython3Bin "steam-input" {
  libraries = [pkgs.python3Packages.vdf];
  flakeIgnore = ["E501"];
} ''
  """Regenerate Steam Input layout templates from a JSON spec."""
  import json
  import os
  import sys

  import vdf

  # Physical input -> the group that owns it. Steam refuses to load a layout
  # that puts one source in two groups, so this mapping is 1:1 by construction.
  GROUPS = [
      ("four_buttons", "button_diamond", ["button_a", "button_b", "button_x", "button_y"]),
      ("dpad", "dpad", ["dpad_north", "dpad_south", "dpad_east", "dpad_west"]),
      ("switches", "switch", [
          "button_escape",      # Start
          "button_menu",        # Select/Back
          "left_bumper",
          "right_bumper",
      ]),
      ("trigger", "left_trigger", ["click"]),
      ("trigger", "right_trigger", ["click"]),
  ]

  # The left stick doubles as a d-pad so menus are navigable with either, and
  # the right stick stays a mouse — the couch tiles are still web pages, and
  # some of what they show has no keyboard path to it at all.
  STICKS = [
      ("dpad", "joystick", {
          "dpad_north": "left_stick_north",
          "dpad_south": "left_stick_south",
          "dpad_east": "left_stick_east",
          "dpad_west": "left_stick_west",
      }),
      ("joystick_camera", "right_joystick", {}),
  ]


  def binding_block(binding):
      """Steam nests every binding under an activator; Full_Press is a plain press."""
      return {"activators": {"Full_Press": {"bindings": {"binding": binding}}}}


  def build_group(group_id, mode, inputs):
      group = {"id": str(group_id), "mode": mode}
      if inputs:
          group["inputs"] = {name: binding_block(b) for name, b in inputs.items()}
      return group


  def build_layout(spec):
      bindings = spec["bindings"]
      unknown = set(bindings) - {
          name
          for _, _, names in GROUPS
          for name in names
          if name != "click"
      } - {"left_trigger", "right_trigger"} - {
          alias for _, _, aliases in STICKS for alias in aliases.values()
      }
      if unknown:
          sys.exit(f"steam-input: unknown input(s): {', '.join(sorted(unknown))}")

      groups = []
      source_bindings = {}
      group_id = 0

      for mode, source, names in GROUPS:
          if mode == "trigger":
              # A trigger's single input is called "click" whichever side it is,
              # so the spec names it by side and it gets renamed here.
              value = bindings.get(source)
              inputs = {"click": value} if value else {}
          else:
              inputs = {n: bindings[n] for n in names if n in bindings}
          if not inputs and mode == "trigger":
              continue
          groups.append(build_group(group_id, mode, inputs))
          source_bindings[str(group_id)] = f"{source} active"
          group_id += 1

      for mode, source, aliases in STICKS:
          inputs = {
              real: bindings[alias]
              for real, alias in aliases.items()
              if alias in bindings
          }
          groups.append(build_group(group_id, mode, inputs))
          source_bindings[str(group_id)] = f"{source} active"
          group_id += 1

      # A layout has one "group" key per group, which a dict can't hold — hence
      # VDFDict, which keeps duplicate keys in order the way the format needs.
      layout = vdf.VDFDict([
          ("version", "3"),
          ("revision", "1"),
          ("title", spec["title"]),
          ("description", spec["description"]),
          ("creator", "0"),
          ("progenitor", ""),
          ("export_type", "personal_local"),
          ("controller_type", spec["controllerType"]),
          ("major_revision", "0"),
          ("minor_revision", "0"),
          ("actions", {"Default": {"title": "Default", "legacy_set": "1"}}),
      ] + [
          ("group", group) for group in groups
      ] + [
          ("preset", {
              "id": "0",
              "name": "Default",
              "group_source_bindings": source_bindings,
          }),
          ("settings", {"left_trackpad_mode": "0", "right_trackpad_mode": "0"}),
      ])
      return vdf.VDFDict([("controller_mappings", layout)])


  def main():
      spec_path, target_dir = sys.argv[1], os.path.expanduser(sys.argv[2])
      specs = json.load(open(spec_path))

      if not os.path.isdir(target_dir):
          # Steam hasn't been unpacked yet; there's nothing to add a template to
          # and creating the tree by hand would just make a directory Steam
          # later replaces. Say so rather than looking like it worked.
          sys.exit(
              f"steam-input: {target_dir} does not exist — run Steam once first"
          )

      # Only ever touch files this module put there. Steam's own templates live
      # in the same directory and are not ours to remove.
      stamp = ".nix-steam-input"
      owned = set()
      stamp_path = os.path.join(target_dir, stamp)
      if os.path.exists(stamp_path):
          owned = set(json.load(open(stamp_path)))

      written = []
      for spec in specs:
          name = f"nix-{spec['slug']}.vdf"
          path = os.path.join(target_dir, name)
          with open(path, "w") as handle:
              vdf.dump(build_layout(spec), handle, pretty=True)
          written.append(name)
          print(f"steam-input: wrote {path}")

      for stale in owned - set(written):
          try:
              os.unlink(os.path.join(target_dir, stale))
              print(f"steam-input: removed {stale}")
          except OSError:
              pass

      with open(stamp_path, "w") as handle:
          json.dump(sorted(written), handle)


  main()
''

# A single-site Firefox kiosk, sized to be added to Steam as a non-Steam
# shortcut so each service gets its own tile in Big Picture.
#
# Browser rather than a native client because the Steam Controller's trackpads
# make point-and-click the pad's native paradigm — and because Nebula (and most
# things like it) ship no client at all. One browser covers every service that
# doesn't have one, instead of a per-service wrapper that breaks when the
# service changes.
#
# Takes the Home Manager `finalPackage` rather than pkgs.firefox so the kiosk
# inherits the configured profile — uBlock and SponsorBlock are the difference
# between this being pleasant and being unusable on a TV.
#
# MOZ_NO_REMOTE is load-bearing: without it a second invocation hands its URL to
# the already-running instance and exits immediately, which Steam reads as the
# shortcut having quit. Exiting is the Steam button -> Exit Game, so there's no
# need for the kind of global kill-key hack eros needed (firefox --kiosk
# swallows Escape and F11).
#
# That makes the dedicated profile mandatory, not cosmetic. Firefox will not
# open one profile twice, so with MOZ_NO_REMOTE every kiosk sharing `default`
# fails to start whenever any other Firefox holds the lock — including one
# Plasma restored from a previous session.
{
  pkgs,
  firefox,
  name,
  url,
  profile,
}:
pkgs.writeShellScriptBin name ''
  export MOZ_ENABLE_WAYLAND=1
  export MOZ_NO_REMOTE=1
  exec ${firefox}/bin/firefox --kiosk -P "${profile}" "${url}"
''

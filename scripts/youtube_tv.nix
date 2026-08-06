# YouTube's TV ("leanback") interface — the same UI a smart TV or Chromecast
# gets, built for d-pad navigation rather than a mouse. This is the whole point
# of the couch YouTube story: arrows + Enter is something Steam Input can map
# onto a controller cleanly, whereas the desktop site assumes a pointer.
#
# youtube.com/tv gates on the user agent and serves the desktop site to anything
# it doesn't recognise as a TV, hence the Chromecast UA below.
#
# Chromium rather than Firefox purely because the UA override is a command-line
# flag here; in Firefox it's a profile pref (general.useragent.override), which
# would mean maintaining a whole separate profile to spoof one string.
#
# The UA is the fragile bit and the first thing to check if this regresses: it
# advertises Chrome/86 against a Chromium that's on 150, and Google has broken
# leanback for stale agents before. Symptom is the desktop YouTube site showing
# up instead of the TV UI; fix is to bump the Chrome and CrKey versions here to
# whatever a current Chromecast reports.
{pkgs}:
pkgs.writeShellScriptBin "youtube-tv" ''
  exec ${pkgs.chromium}/bin/chromium \
    --kiosk \
    --ozone-platform-hint=auto \
    --user-agent="Mozilla/5.0 (X11; Linux armv7l) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/86.0.4240.193 Safari/537.36 CrKey/1.54.250320" \
    --autoplay-policy=no-user-gesture-required \
    --no-first-run \
    --no-default-browser-check \
    --disable-features=Translate \
    "https://www.youtube.com/tv" "$@"
''
